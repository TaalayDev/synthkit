#include "include/synthkit/synth_kit_plugin.h"

#include <alsa/asoundlib.h>
#include <errno.h>
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <algorithm>
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

#define SYNTHKIT_PLUGIN(obj)                                         \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), synth_kit_plugin_get_type(),    \
                              SynthKitPlugin))

class LinuxSynthKitEngine;

struct _SynthKitPlugin {
  GObject parent_instance;
  LinuxSynthKitEngine* engine;
};

G_DEFINE_TYPE(SynthKitPlugin, synth_kit_plugin, g_object_get_type())

constexpr int kSampleRate = 44100;
constexpr int kChannels = 2;
constexpr size_t kBufferFrames = 512;
constexpr double kPi = 3.14159265358979323846;

using Clock = std::chrono::steady_clock;

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

struct ScheduledNote {
  std::string synth_id;
  SynthSpec spec;
  double frequency_hz = 440.0;
  int duration_ms = 500;
  double velocity = 1.0;
  Clock::time_point due_at;
};

FlValue* GetMapValue(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  return fl_value_lookup_string(map, key);
}

std::optional<std::string> GetString(FlValue* map, const char* key) {
  FlValue* value = GetMapValue(map, key);
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
    return fl_value_get_string(value);
  }
  return std::nullopt;
}

double GetDouble(FlValue* map, const char* key, double fallback) {
  FlValue* value = GetMapValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(value));
  }
  return fallback;
}

int GetInt(FlValue* map, const char* key, int fallback) {
  FlValue* value = GetMapValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<int>(fl_value_get_int(value));
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int>(fl_value_get_float(value));
  }
  return fallback;
}

bool GetBool(FlValue* map, const char* key, bool fallback) {
  FlValue* value = GetMapValue(map, key);
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL) {
    return fl_value_get_bool(value);
  }
  return fallback;
}

std::string RequireString(FlValue* map, const char* key) {
  const auto value = GetString(map, key);
  if (!value.has_value() || value->empty()) {
    throw std::runtime_error(std::string("Missing ") + key + ".");
  }
  return *value;
}

SynthSpec ParseSynthSpec(FlValue* args) {
  SynthSpec spec;
  spec.waveform = GetString(args, "waveform").value_or("sine");
  spec.volume = GetDouble(args, "volume", 0.8);

  FlValue* envelope = GetMapValue(args, "envelope");
  if (envelope != nullptr && fl_value_get_type(envelope) == FL_VALUE_TYPE_MAP) {
    spec.envelope.attack_ms = GetInt(envelope, "attackMs", 10);
    spec.envelope.decay_ms = GetInt(envelope, "decayMs", 120);
    spec.envelope.sustain = GetDouble(envelope, "sustain", 0.75);
    spec.envelope.release_ms = GetInt(envelope, "releaseMs", 240);
  }

  FlValue* filter = GetMapValue(args, "filter");
  if (filter != nullptr && fl_value_get_type(filter) == FL_VALUE_TYPE_MAP) {
    spec.filter.enabled = GetBool(filter, "enabled", false);
    spec.filter.cutoff_hz = GetDouble(filter, "cutoffHz", 1800.0);
  }

  return spec;
}

FlValue* RequireMap(FlValue* value, const char* message) {
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_MAP) {
    throw std::runtime_error(message);
  }
  return value;
}

std::runtime_error AlsaError(const std::string& context, int code) {
  return std::runtime_error(
      context + ": " + std::string(snd_strerror(code)));
}

class LinuxSynthKitEngine {
 public:
  LinuxSynthKitEngine() = default;

  ~LinuxSynthKitEngine() { Dispose(); }

  void Initialize(double master_volume) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      master_volume_ = std::clamp(master_volume, 0.0, 1.0);
      if (running_) {
        return;
      }
    }

    OpenPcmDevice();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      running_ = true;
    }

    scheduler_thread_ = std::thread([this]() { SchedulerLoop(); });
    render_thread_ = std::thread([this]() { RenderLoop(); });
  }

  void Dispose() {
    snd_pcm_t* pcm_handle = nullptr;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!running_ && pcm_handle_ == nullptr) {
        synths_.clear();
        scheduled_.clear();
        voices_.clear();
        return;
      }

      running_ = false;
      scheduled_.clear();
      voices_.clear();
      synths_.clear();
      pcm_handle = pcm_handle_;
    }
    cv_.notify_all();

    if (pcm_handle != nullptr) {
      snd_pcm_drop(pcm_handle);
    }

    if (scheduler_thread_.joinable()) {
      scheduler_thread_.join();
    }
    if (render_thread_.joinable()) {
      render_thread_.join();
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      pcm_handle = pcm_handle_;
      pcm_handle_ = nullptr;
    }
    if (pcm_handle != nullptr) {
      snd_pcm_close(pcm_handle);
    }
  }

  void SetMasterVolume(double volume) {
    std::lock_guard<std::mutex> lock(mutex_);
    master_volume_ = std::clamp(volume, 0.0, 1.0);
  }

  std::string CreateSynth(const SynthSpec& spec) {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::string synth_id = "linux_synth_" + std::to_string(next_synth_id_++);
    synths_[synth_id] = spec;
    return synth_id;
  }

  void UpdateSynth(const std::string& synth_id, const SynthSpec& spec) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (synths_.find(synth_id) == synths_.end()) {
      throw std::runtime_error("Unknown synth id: " + synth_id);
    }
    synths_[synth_id] = spec;
  }

  void TriggerNote(const std::string& synth_id, double frequency_hz,
                   int duration_ms, double velocity, int delay_ms) {
    ScheduledNote note;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = synths_.find(synth_id);
      if (it == synths_.end()) {
        throw std::runtime_error("Unknown synth id: " + synth_id);
      }
      note.synth_id = synth_id;
      note.spec = it->second;
      note.frequency_hz = frequency_hz;
      note.duration_ms = duration_ms;
      note.velocity = velocity;
      note.due_at = Clock::now() + std::chrono::milliseconds(std::max(delay_ms, 0));
      if (delay_ms <= 0) {
        voices_.emplace_back(note.spec, note.frequency_hz, note.duration_ms,
                             note.velocity);
        return;
      }
      scheduled_.push_back(note);
    }
    cv_.notify_all();
  }

  void CancelScheduledNotes(const std::optional<std::string>& synth_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (synth_id.has_value()) {
      scheduled_.erase(
          std::remove_if(scheduled_.begin(), scheduled_.end(),
                         [&](const ScheduledNote& note) {
                           return note.synth_id == *synth_id;
                         }),
          scheduled_.end());
    } else {
      scheduled_.clear();
    }
    cv_.notify_all();
  }

  void Panic() {
    std::lock_guard<std::mutex> lock(mutex_);
    scheduled_.clear();
    voices_.clear();
    cv_.notify_all();
  }

  void DisposeSynth(const std::string& synth_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    synths_.erase(synth_id);
    scheduled_.erase(
        std::remove_if(scheduled_.begin(), scheduled_.end(),
                       [&](const ScheduledNote& note) {
                         return note.synth_id == synth_id;
                       }),
        scheduled_.end());
  }

 private:
  void OpenPcmDevice() {
    snd_pcm_t* pcm_handle = nullptr;
    int error = snd_pcm_open(&pcm_handle, "default", SND_PCM_STREAM_PLAYBACK, 0);
    if (error < 0) {
      throw AlsaError("Failed to open the default ALSA playback device", error);
    }

    error = snd_pcm_set_params(
        pcm_handle, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
        kChannels, kSampleRate, 1, 50000);
    if (error < 0) {
      snd_pcm_close(pcm_handle);
      throw AlsaError("Failed to configure the ALSA playback device", error);
    }

    error = snd_pcm_prepare(pcm_handle);
    if (error < 0) {
      snd_pcm_close(pcm_handle);
      throw AlsaError("Failed to prepare the ALSA playback device", error);
    }

    std::lock_guard<std::mutex> lock(mutex_);
    pcm_handle_ = pcm_handle;
  }

  void SchedulerLoop() {
    std::unique_lock<std::mutex> lock(mutex_);
    while (running_) {
      if (scheduled_.empty()) {
        cv_.wait(lock, [&]() { return !running_ || !scheduled_.empty(); });
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

      const auto now = Clock::now();
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
      WriteFrames(buffer.data(), kBufferFrames);
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

  void WriteFrames(const int16_t* data, size_t frame_count) {
    snd_pcm_t* pcm_handle = nullptr;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      pcm_handle = pcm_handle_;
    }
    if (pcm_handle == nullptr) {
      return;
    }

    size_t offset = 0;
    while (offset < frame_count && IsRunning()) {
      const snd_pcm_sframes_t written = snd_pcm_writei(
          pcm_handle, data + (offset * kChannels), frame_count - offset);
      if (written > 0) {
        offset += static_cast<size_t>(written);
        continue;
      }

      if (written == -EAGAIN) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        continue;
      }

      const int recovered = snd_pcm_recover(pcm_handle, static_cast<int>(written), 1);
      if (recovered >= 0) {
        continue;
      }

      if (!IsRunning()) {
        return;
      }

      std::this_thread::sleep_for(std::chrono::milliseconds(10));
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
  int next_synth_id_ = 1;
  snd_pcm_t* pcm_handle_ = nullptr;
  std::thread scheduler_thread_;
  std::thread render_thread_;
  std::unordered_map<std::string, SynthSpec> synths_;
  std::vector<ScheduledNote> scheduled_;
  std::vector<Voice> voices_;
};

FlMethodResponse* SuccessResponse() {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

FlMethodResponse* StringResponse(const char* value) {
  g_autoptr(FlValue) result = fl_value_new_string(value);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

FlMethodResponse* ErrorResponse(const std::string& message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new("synthkit/error", message.c_str(), nullptr));
}

FlMethodResponse* HandleMethodCall(SynthKitPlugin* self,
                                   FlMethodCall* method_call) {
  try {
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);

    if (strcmp(method, "getBackendName") == 0) {
      return StringResponse("native-linux");
    }

    if (strcmp(method, "initialize") == 0) {
      self->engine->Initialize(GetDouble(
          RequireMap(args, "Expected an argument map."), "masterVolume", 0.8));
      return SuccessResponse();
    }

    if (strcmp(method, "disposeEngine") == 0) {
      self->engine->Dispose();
      return SuccessResponse();
    }

    if (strcmp(method, "setMasterVolume") == 0) {
      self->engine->SetMasterVolume(GetDouble(
          RequireMap(args, "Expected an argument map."), "volume", 0.8));
      return SuccessResponse();
    }

    if (strcmp(method, "createSynth") == 0) {
      args = RequireMap(args, "Expected a synth config map.");
      const std::string synth_id =
          self->engine->CreateSynth(ParseSynthSpec(args));
      g_autoptr(FlValue) result = fl_value_new_string(synth_id.c_str());
      return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }

    if (strcmp(method, "updateSynth") == 0) {
      args = RequireMap(args, "Expected a synth config map.");
      self->engine->UpdateSynth(RequireString(args, "synthId"),
                                ParseSynthSpec(args));
      return SuccessResponse();
    }

    if (strcmp(method, "triggerNote") == 0) {
      args = RequireMap(args, "Expected a trigger note map.");
      self->engine->TriggerNote(RequireString(args, "synthId"),
                                GetDouble(args, "frequencyHz", 440.0),
                                GetInt(args, "durationMs", 500),
                                GetDouble(args, "velocity", 1.0),
                                GetInt(args, "delayMs", 0));
      return SuccessResponse();
    }

    if (strcmp(method, "cancelScheduledNotes") == 0) {
      if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
        self->engine->CancelScheduledNotes(GetString(args, "synthId"));
      } else {
        self->engine->CancelScheduledNotes(std::nullopt);
      }
      return SuccessResponse();
    }

    if (strcmp(method, "panic") == 0) {
      self->engine->Panic();
      return SuccessResponse();
    }

    if (strcmp(method, "disposeSynth") == 0) {
      args = RequireMap(args, "Expected a synth id map.");
      self->engine->DisposeSynth(RequireString(args, "synthId"));
      return SuccessResponse();
    }

    return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } catch (const std::exception& error) {
    return ErrorResponse(error.what());
  }
}

static void synth_kit_plugin_handle_method_call(SynthKitPlugin* self,
                                                FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = HandleMethodCall(self, method_call);
  fl_method_call_respond(method_call, response, nullptr);
}

static void synth_kit_plugin_dispose(GObject* object) {
  SynthKitPlugin* self = SYNTHKIT_PLUGIN(object);
  delete self->engine;
  self->engine = nullptr;

  G_OBJECT_CLASS(synth_kit_plugin_parent_class)->dispose(object);
}

static void synth_kit_plugin_class_init(SynthKitPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = synth_kit_plugin_dispose;
}

static void synth_kit_plugin_init(SynthKitPlugin* self) {
  self->engine = new LinuxSynthKitEngine();
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  SynthKitPlugin* plugin = SYNTHKIT_PLUGIN(user_data);
  synth_kit_plugin_handle_method_call(plugin, method_call);
}

void synth_kit_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  SynthKitPlugin* plugin = SYNTHKIT_PLUGIN(
      g_object_new(synth_kit_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "synthkit",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
