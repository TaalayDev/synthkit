#include <jni.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

constexpr int kSampleRate = 44100;
constexpr int kChannels = 2;
constexpr size_t kBufferFrames = 256;
constexpr double kPi = 3.14159265358979323846;

JavaVM* g_jvm = nullptr;
thread_local std::string g_last_error;

struct EnvelopeSpec {
  int attack_ms = 10;
  int decay_ms = 120;
  double sustain = 0.75;
  int release_ms = 240;
};

struct FilterSpec {
  bool enabled = false;
  double cutoff_hz = 1800.0;
};

struct SynthSpec {
  std::string waveform = "sine";
  double volume = 0.8;
  EnvelopeSpec envelope;
  FilterSpec filter;
};

struct ScheduledNote {
  int32_t synth_handle = 0;
  SynthSpec spec;
  double frequency_hz = 440.0;
  int duration_ms = 500;
  double velocity = 1.0;
  std::chrono::steady_clock::time_point due_at;
};

class Voice {
 public:
  Voice(const SynthSpec& spec, double frequency_hz, int duration_ms,
        double velocity)
      : waveform_(spec.waveform),
        filter_enabled_(spec.filter.enabled),
        cutoff_hz_(std::max(10.0, spec.filter.cutoff_hz)),
        attack_s_(std::max(spec.envelope.attack_ms / 1000.0, 0.0)),
        decay_s_(std::max(spec.envelope.decay_ms / 1000.0, 0.0)),
        sustain_(std::clamp(spec.envelope.sustain, 0.0, 1.0)),
        release_s_(std::max(spec.envelope.release_ms / 1000.0, 0.0)),
        note_duration_s_(std::max(duration_ms / 1000.0, 0.001)),
        total_duration_s_(note_duration_s_ + std::max(release_s_, 0.001)),
        frequency_hz_(frequency_hz),
        amplitude_(std::clamp(velocity, 0.0, 1.0) *
                   std::clamp(spec.volume, 0.0, 1.0)) {
    if (filter_enabled_) {
      const double dt = 1.0 / static_cast<double>(kSampleRate);
      const double rc = 1.0 / (2.0 * kPi * cutoff_hz_);
      lowpass_alpha_ = dt / (rc + dt);
    }
  }

  double NextSample() {
    const double envelope = EnvelopeAt(elapsed_s_);
    double oscillator = 0.0;
    if (waveform_ == "square") {
      oscillator = phase_ < 0.5 ? 1.0 : -1.0;
    } else if (waveform_ == "triangle") {
      oscillator = 1.0 - 4.0 * std::abs(phase_ - 0.5);
    } else if (waveform_ == "sawtooth") {
      oscillator = (2.0 * phase_) - 1.0;
    } else {
      oscillator = std::sin(phase_ * 2.0 * kPi);
    }

    const double dry = oscillator * envelope * amplitude_;
    double wet = dry;
    if (filter_enabled_) {
      filter_state_ += lowpass_alpha_ * (dry - filter_state_);
      wet = filter_state_;
    }

    phase_ += frequency_hz_ / static_cast<double>(kSampleRate);
    if (phase_ >= 1.0) {
      phase_ -= std::floor(phase_);
    }
    elapsed_s_ += 1.0 / static_cast<double>(kSampleRate);
    return wet;
  }

  bool IsFinished() const { return elapsed_s_ >= total_duration_s_; }

 private:
  double EnvelopeAt(double seconds) const {
    if (attack_s_ > 0.0 && seconds < attack_s_) {
      return seconds / attack_s_;
    }

    const double decay_start = attack_s_;
    const double decay_end = decay_start + decay_s_;
    if (decay_s_ > 0.0 && seconds < decay_end) {
      const double progress = (seconds - decay_start) / decay_s_;
      return 1.0 - ((1.0 - sustain_) * progress);
    }

    if (seconds < note_duration_s_) {
      return sustain_;
    }

    if (release_s_ > 0.0 && seconds < total_duration_s_) {
      const double progress = (seconds - note_duration_s_) / release_s_;
      return sustain_ * (1.0 - std::clamp(progress, 0.0, 1.0));
    }

    return 0.0;
  }

  std::string waveform_;
  bool filter_enabled_ = false;
  double cutoff_hz_ = 1800.0;
  double attack_s_ = 0.0;
  double decay_s_ = 0.0;
  double sustain_ = 0.75;
  double release_s_ = 0.0;
  double note_duration_s_ = 0.1;
  double total_duration_s_ = 0.2;
  double frequency_hz_ = 440.0;
  double amplitude_ = 0.8;
  double elapsed_s_ = 0.0;
  double phase_ = 0.0;
  double filter_state_ = 0.0;
  double lowpass_alpha_ = 1.0;
};

class ScopedEnv {
 public:
  ScopedEnv() {
    if (g_jvm == nullptr) {
      throw std::runtime_error("JavaVM is unavailable.");
    }
    const jint status =
        g_jvm->GetEnv(reinterpret_cast<void**>(&env_), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
      if (g_jvm->AttachCurrentThread(&env_, nullptr) != JNI_OK) {
        throw std::runtime_error("Failed to attach the native audio thread.");
      }
      attached_ = true;
    } else if (status != JNI_OK) {
      throw std::runtime_error("Failed to acquire JNIEnv.");
    }
  }

  ~ScopedEnv() {
    if (attached_ && g_jvm != nullptr) {
      g_jvm->DetachCurrentThread();
    }
  }

  JNIEnv* get() const { return env_; }

 private:
  JNIEnv* env_ = nullptr;
  bool attached_ = false;
};

class AudioTrackBridge {
 public:
  AudioTrackBridge() = default;
  ~AudioTrackBridge() { Close(); }

  void Open() {
    ScopedEnv scoped_env;
    JNIEnv* env = scoped_env.get();

    jclass local_class = env->FindClass("android/media/AudioTrack");
    if (local_class == nullptr) {
      throw std::runtime_error("Unable to find android.media.AudioTrack.");
    }
    audio_track_class_ = reinterpret_cast<jclass>(env->NewGlobalRef(local_class));
    env->DeleteLocalRef(local_class);

    const jint min_buffer_size =
        env->CallStaticIntMethod(audio_track_class_, GetMinBufferSize(env),
                                 kSampleRate, 12, 2);
    if (CheckException(env, "AudioTrack.getMinBufferSize() failed.")) {
      return;
    }

    const jint desired_buffer_size =
        std::max(min_buffer_size, static_cast<jint>(kBufferFrames * kChannels * 2 * 4));

    jobject local_track = env->NewObject(audio_track_class_, GetConstructor(env), 3,
                                         kSampleRate, 12, 2, desired_buffer_size, 1);
    if (local_track == nullptr || CheckException(env, "Failed to create AudioTrack.")) {
      return;
    }
    audio_track_ = env->NewGlobalRef(local_track);
    env->DeleteLocalRef(local_track);

    env->CallVoidMethod(audio_track_, GetPlay(env));
    CheckException(env, "AudioTrack.play() failed.");
  }

  void Write(const int16_t* data, size_t sample_count) {
    ScopedEnv scoped_env;
    JNIEnv* env = scoped_env.get();
    if (audio_track_ == nullptr) {
      return;
    }

    jshortArray buffer = env->NewShortArray(static_cast<jsize>(sample_count));
    if (buffer == nullptr) {
      throw std::runtime_error("Failed to allocate JNI audio buffer.");
    }
    env->SetShortArrayRegion(buffer, 0, static_cast<jsize>(sample_count),
                             reinterpret_cast<const jshort*>(data));
    if (CheckException(env, "Failed to upload audio samples.")) {
      env->DeleteLocalRef(buffer);
      return;
    }

    env->CallIntMethod(audio_track_, GetWrite(env), buffer, 0,
                       static_cast<jint>(sample_count), 0);
    CheckException(env, "AudioTrack.write() failed.");
    env->DeleteLocalRef(buffer);
  }

  void Close() {
    if (audio_track_ == nullptr && audio_track_class_ == nullptr) {
      return;
    }

    ScopedEnv scoped_env;
    JNIEnv* env = scoped_env.get();

    if (audio_track_ != nullptr) {
      env->CallVoidMethod(audio_track_, GetPause(env));
      env->ExceptionClear();
      env->CallVoidMethod(audio_track_, GetFlush(env));
      env->ExceptionClear();
      env->CallVoidMethod(audio_track_, GetRelease(env));
      env->ExceptionClear();
      env->DeleteGlobalRef(audio_track_);
      audio_track_ = nullptr;
    }

    if (audio_track_class_ != nullptr) {
      env->DeleteGlobalRef(audio_track_class_);
      audio_track_class_ = nullptr;
    }
  }

 private:
  bool CheckException(JNIEnv* env, const char* fallback_message) {
    if (!env->ExceptionCheck()) {
      return false;
    }
    env->ExceptionClear();
    throw std::runtime_error(fallback_message);
  }

  jmethodID GetMinBufferSize(JNIEnv* env) {
    if (get_min_buffer_size_ == nullptr) {
      get_min_buffer_size_ =
          env->GetStaticMethodID(audio_track_class_, "getMinBufferSize", "(III)I");
    }
    return get_min_buffer_size_;
  }

  jmethodID GetConstructor(JNIEnv* env) {
    if (constructor_ == nullptr) {
      constructor_ = env->GetMethodID(audio_track_class_, "<init>", "(IIIIII)V");
    }
    return constructor_;
  }

  jmethodID GetPlay(JNIEnv* env) {
    if (play_ == nullptr) {
      play_ = env->GetMethodID(audio_track_class_, "play", "()V");
    }
    return play_;
  }

  jmethodID GetPause(JNIEnv* env) {
    if (pause_ == nullptr) {
      pause_ = env->GetMethodID(audio_track_class_, "pause", "()V");
    }
    return pause_;
  }

  jmethodID GetFlush(JNIEnv* env) {
    if (flush_ == nullptr) {
      flush_ = env->GetMethodID(audio_track_class_, "flush", "()V");
    }
    return flush_;
  }

  jmethodID GetRelease(JNIEnv* env) {
    if (release_ == nullptr) {
      release_ = env->GetMethodID(audio_track_class_, "release", "()V");
    }
    return release_;
  }

  jmethodID GetWrite(JNIEnv* env) {
    if (write_ == nullptr) {
      write_ =
          env->GetMethodID(audio_track_class_, "write", "([SIII)I");
    }
    return write_;
  }

  jclass audio_track_class_ = nullptr;
  jobject audio_track_ = nullptr;
  jmethodID get_min_buffer_size_ = nullptr;
  jmethodID constructor_ = nullptr;
  jmethodID play_ = nullptr;
  jmethodID pause_ = nullptr;
  jmethodID flush_ = nullptr;
  jmethodID release_ = nullptr;
  jmethodID write_ = nullptr;
};

SynthSpec ParseSynthSpec(int waveform, double volume, int attack_ms,
                         int decay_ms, double sustain, int release_ms,
                         int filter_enabled, double cutoff_hz) {
  SynthSpec spec;
  switch (waveform) {
    case 1:
      spec.waveform = "square";
      break;
    case 2:
      spec.waveform = "triangle";
      break;
    case 3:
      spec.waveform = "sawtooth";
      break;
    default:
      spec.waveform = "sine";
      break;
  }
  spec.volume = volume;
  spec.envelope.attack_ms = attack_ms;
  spec.envelope.decay_ms = decay_ms;
  spec.envelope.sustain = sustain;
  spec.envelope.release_ms = release_ms;
  spec.filter.enabled = filter_enabled != 0;
  spec.filter.cutoff_hz = cutoff_hz;
  return spec;
}

template <typename Callback>
int32_t WrapFfiCall(Callback&& callback) {
  try {
    callback();
    g_last_error.clear();
    return 1;
  } catch (const std::exception& error) {
    g_last_error = error.what();
    return 0;
  } catch (...) {
    g_last_error = "Unknown FFI error.";
    return 0;
  }
}

class AndroidFfiBridge {
 public:
  AndroidFfiBridge() = default;
  ~AndroidFfiBridge() { DisposeEngine(); }

  void Initialize(double master_volume) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      master_volume_ = std::clamp(master_volume, 0.0, 1.0);
      if (running_) {
        return;
      }
    }

    audio_track_.Open();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      running_ = true;
    }
    scheduler_thread_ = std::thread([this]() { SchedulerLoop(); });
    render_thread_ = std::thread([this]() { RenderLoop(); });
  }

  void DisposeEngine() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!running_) {
        synths_.clear();
        scheduled_.clear();
        voices_.clear();
        return;
      }
      running_ = false;
      synths_.clear();
      scheduled_.clear();
      voices_.clear();
    }
    cv_.notify_all();
    if (scheduler_thread_.joinable()) {
      scheduler_thread_.join();
    }
    if (render_thread_.joinable()) {
      render_thread_.join();
    }
    audio_track_.Close();
  }

  void SetMasterVolume(double volume) {
    std::lock_guard<std::mutex> lock(mutex_);
    master_volume_ = std::clamp(volume, 0.0, 1.0);
  }

  int32_t CreateSynth(const SynthSpec& spec) {
    std::lock_guard<std::mutex> lock(mutex_);
    const int32_t handle = next_synth_handle_++;
    synths_[handle] = spec;
    return handle;
  }

  void UpdateSynth(int32_t synth_handle, const SynthSpec& spec) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = synths_.find(synth_handle);
    if (it == synths_.end()) {
      throw std::runtime_error("Unknown ffi synth handle: " +
                               std::to_string(synth_handle));
    }
    it->second = spec;
  }

  void TriggerNote(int32_t synth_handle, double frequency_hz, int duration_ms,
                   double velocity, int delay_ms) {
    ScheduledNote note;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      const auto it = synths_.find(synth_handle);
      if (it == synths_.end()) {
        throw std::runtime_error("Unknown ffi synth handle: " +
                                 std::to_string(synth_handle));
      }
      note.synth_handle = synth_handle;
      note.spec = it->second;
      note.frequency_hz = frequency_hz;
      note.duration_ms = duration_ms;
      note.velocity = std::clamp(velocity, 0.0, 1.0);
      note.due_at = std::chrono::steady_clock::now() +
                    std::chrono::milliseconds(std::max(delay_ms, 0));
      if (delay_ms <= 0) {
        voices_.emplace_back(note.spec, note.frequency_hz, note.duration_ms,
                             note.velocity);
        return;
      }
      scheduled_.push_back(note);
    }
    cv_.notify_all();
  }

  void CancelScheduledNotes(int32_t synth_handle) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (synth_handle < 0) {
      scheduled_.clear();
    } else {
      scheduled_.erase(
          std::remove_if(scheduled_.begin(), scheduled_.end(),
                         [&](const ScheduledNote& note) {
                           return note.synth_handle == synth_handle;
                         }),
          scheduled_.end());
    }
    cv_.notify_all();
  }

  void Panic() {
    std::lock_guard<std::mutex> lock(mutex_);
    scheduled_.clear();
    voices_.clear();
    cv_.notify_all();
  }

  void DisposeSynth(int32_t synth_handle) {
    std::lock_guard<std::mutex> lock(mutex_);
    synths_.erase(synth_handle);
    scheduled_.erase(
        std::remove_if(scheduled_.begin(), scheduled_.end(),
                       [&](const ScheduledNote& note) {
                         return note.synth_handle == synth_handle;
                       }),
        scheduled_.end());
  }

 private:
  void SchedulerLoop() {
    std::unique_lock<std::mutex> lock(mutex_);
    while (running_) {
      if (scheduled_.empty()) {
        cv_.wait(lock, [&] { return !running_ || !scheduled_.empty(); });
        continue;
      }

      const auto next_it = std::min_element(
          scheduled_.begin(), scheduled_.end(),
          [](const ScheduledNote& left, const ScheduledNote& right) {
            return left.due_at < right.due_at;
          });

      cv_.wait_until(lock, next_it->due_at);
      if (!running_) {
        continue;
      }

      const auto now = std::chrono::steady_clock::now();
      std::vector<ScheduledNote> due_notes;
      for (auto it = scheduled_.begin(); it != scheduled_.end();) {
        if (it->due_at <= now) {
          due_notes.push_back(*it);
          it = scheduled_.erase(it);
        } else {
          ++it;
        }
      }

      for (const auto& note : due_notes) {
        voices_.emplace_back(note.spec, note.frequency_hz, note.duration_ms,
                             note.velocity);
      }
    }
  }

  void RenderLoop() {
    std::vector<int16_t> buffer(kBufferFrames * kChannels);
    while (IsRunning()) {
      FillBuffer(buffer);
      audio_track_.Write(buffer.data(), buffer.size());
    }
  }

  void FillBuffer(std::vector<int16_t>& buffer) {
    std::lock_guard<std::mutex> lock(mutex_);
    for (size_t frame = 0; frame < kBufferFrames; ++frame) {
      double mixed = 0.0;
      for (auto it = voices_.begin(); it != voices_.end();) {
        mixed += it->NextSample();
        if (it->IsFinished()) {
          it = voices_.erase(it);
        } else {
          ++it;
        }
      }
      const double sample = std::clamp(mixed * master_volume_, -1.0, 1.0);
      const int16_t encoded =
          static_cast<int16_t>(sample * static_cast<double>(INT16_MAX));
      buffer[frame * kChannels] = encoded;
      buffer[frame * kChannels + 1] = encoded;
    }
  }

  bool IsRunning() {
    std::lock_guard<std::mutex> lock(mutex_);
    return running_;
  }

  std::mutex mutex_;
  std::condition_variable cv_;
  bool running_ = false;
  double master_volume_ = 0.8;
  int32_t next_synth_handle_ = 1;
  AudioTrackBridge audio_track_;
  std::thread scheduler_thread_;
  std::thread render_thread_;
  std::unordered_map<int32_t, SynthSpec> synths_;
  std::vector<ScheduledNote> scheduled_;
  std::vector<Voice> voices_;
};

AndroidFfiBridge& GetBridge() {
  static AndroidFfiBridge bridge;
  return bridge;
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  g_jvm = vm;
  return JNI_VERSION_1_6;
}

extern "C" {

int32_t synthkit_ffi_is_supported() { return 1; }

int32_t synthkit_ffi_get_backend_name() {
  g_last_error = "ffi-android";
  return 1;
}

const char* synthkit_ffi_last_error_message() { return g_last_error.c_str(); }

int32_t synthkit_ffi_initialize(double master_volume) {
  return WrapFfiCall([&]() { GetBridge().Initialize(master_volume); });
}

void synthkit_ffi_dispose_engine() { GetBridge().DisposeEngine(); }

int32_t synthkit_ffi_set_master_volume(double volume) {
  return WrapFfiCall([&]() { GetBridge().SetMasterVolume(volume); });
}

int32_t synthkit_ffi_create_synth(int32_t waveform, double volume,
                                  int32_t attack_ms, int32_t decay_ms,
                                  double sustain, int32_t release_ms,
                                  int32_t filter_enabled, double cutoff_hz) {
  int32_t synth_handle = 0;
  const auto spec =
      ParseSynthSpec(waveform, volume, attack_ms, decay_ms, sustain,
                     release_ms, filter_enabled, cutoff_hz);
  const int32_t status =
      WrapFfiCall([&]() { synth_handle = GetBridge().CreateSynth(spec); });
  return status == 1 ? synth_handle : 0;
}

int32_t synthkit_ffi_update_synth(int32_t synth_handle, int32_t waveform,
                                  double volume, int32_t attack_ms,
                                  int32_t decay_ms, double sustain,
                                  int32_t release_ms, int32_t filter_enabled,
                                  double cutoff_hz) {
  const auto spec =
      ParseSynthSpec(waveform, volume, attack_ms, decay_ms, sustain,
                     release_ms, filter_enabled, cutoff_hz);
  return WrapFfiCall(
      [&]() { GetBridge().UpdateSynth(synth_handle, spec); });
}

int32_t synthkit_ffi_trigger_note(int32_t synth_handle, double frequency_hz,
                                  int32_t duration_ms, double velocity,
                                  int32_t delay_ms) {
  return WrapFfiCall([&]() {
    GetBridge().TriggerNote(synth_handle, frequency_hz, duration_ms, velocity,
                            delay_ms);
  });
}

int32_t synthkit_ffi_cancel_scheduled_notes(int32_t synth_handle) {
  return WrapFfiCall(
      [&]() { GetBridge().CancelScheduledNotes(synth_handle); });
}

int32_t synthkit_ffi_panic() {
  return WrapFfiCall([&]() { GetBridge().Panic(); });
}

int32_t synthkit_ffi_dispose_synth(int32_t synth_handle) {
  return WrapFfiCall([&]() { GetBridge().DisposeSynth(synth_handle); });
}

}
