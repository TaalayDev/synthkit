#include "synthkit_plugin.h"

#include <windows.h>
#include <mmsystem.h>

#include <flutter/plugin_registrar_windows.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

namespace synthkit {

namespace {

constexpr int kSampleRate = 44100;
constexpr int kChannels = 2;
constexpr size_t kBufferFrames = 512;
constexpr size_t kBufferCount = 4;
constexpr double kPi = 3.14159265358979323846;

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
  std::chrono::steady_clock::time_point due_at;
};

SynthSpec FfiParseSynthSpec(int waveform, double volume, int attack_ms,
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

}  // namespace

class WindowsSynthKitEngine {
 public:
  WindowsSynthKitEngine() = default;

  ~WindowsSynthKitEngine() { Dispose(); }

  void Initialize(double master_volume) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      master_volume_ = std::clamp(master_volume, 0.0, 1.0);
      if (running_) {
        return;
      }
    }

    OpenWaveOut();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      running_ = true;
    }
    scheduler_thread_ =
        std::thread([this]() { SchedulerLoop(); });
    render_thread_ = std::thread([this]() { RenderLoop(); });
  }

  void Dispose() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!running_) {
        synths_.clear();
        scheduled_.clear();
        voices_.clear();
        return;
      }
      running_ = false;
      scheduled_.clear();
      voices_.clear();
      synths_.clear();
    }
    cv_.notify_all();

    if (scheduler_thread_.joinable()) {
      scheduler_thread_.join();
    }
    if (render_thread_.joinable()) {
      render_thread_.join();
    }

    if (wave_out_ != nullptr) {
      waveOutReset(wave_out_);
      for (auto& header : headers_) {
        if (header.dwFlags & WHDR_PREPARED) {
          waveOutUnprepareHeader(wave_out_, &header, sizeof(WAVEHDR));
        }
      }
      waveOutClose(wave_out_);
      wave_out_ = nullptr;
    }
  }

  void SetMasterVolume(double volume) {
    std::lock_guard<std::mutex> lock(mutex_);
    master_volume_ = std::clamp(volume, 0.0, 1.0);
  }

  std::string CreateSynth(const SynthSpec& spec) {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::string synth_id =
        "windows_synth_" + std::to_string(next_synth_id_++);
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
  void OpenWaveOut() {
    WAVEFORMATEX format = {};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = static_cast<WORD>(kChannels);
    format.nSamplesPerSec = kSampleRate;
    format.wBitsPerSample = 16;
    format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
    format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;

    const MMRESULT result =
        waveOutOpen(&wave_out_, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL);
    if (result != MMSYSERR_NOERROR) {
      throw std::runtime_error("Failed to open Windows audio output.");
    }

    for (size_t i = 0; i < kBufferCount; ++i) {
      buffers_[i].resize(kBufferFrames * kChannels);
      headers_[i] = {};
      headers_[i].lpData =
          reinterpret_cast<LPSTR>(buffers_[i].data());
      headers_[i].dwBufferLength =
          static_cast<DWORD>(buffers_[i].size() * sizeof(int16_t));
      waveOutPrepareHeader(wave_out_, &headers_[i], sizeof(WAVEHDR));
      FillBuffer(buffers_[i]);
      waveOutWrite(wave_out_, &headers_[i], sizeof(WAVEHDR));
    }
  }

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
    while (true) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_) {
          break;
        }
      }

      for (size_t i = 0; i < kBufferCount; ++i) {
        if ((headers_[i].dwFlags & WHDR_DONE) == 0) {
          continue;
        }
        FillBuffer(buffers_[i]);
        headers_[i].dwFlags &= ~WHDR_DONE;
        waveOutWrite(wave_out_, &headers_[i], sizeof(WAVEHDR));
      }

      std::this_thread::sleep_for(std::chrono::milliseconds(4));
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
      const double sample =
          std::clamp(mixed * master_volume_, -1.0, 1.0);
      const int16_t encoded =
          static_cast<int16_t>(sample * static_cast<double>(INT16_MAX));
      buffer[frame * kChannels] = encoded;
      buffer[frame * kChannels + 1] = encoded;
    }
  }

  std::mutex mutex_;
  std::condition_variable cv_;
  bool running_ = false;
  double master_volume_ = 0.8;
  int next_synth_id_ = 1;
  HWAVEOUT wave_out_ = nullptr;
  std::array<WAVEHDR, kBufferCount> headers_{};
  std::array<std::vector<int16_t>, kBufferCount> buffers_{};
  std::thread scheduler_thread_;
  std::thread render_thread_;
  std::unordered_map<std::string, SynthSpec> synths_;
  std::vector<ScheduledNote> scheduled_;
  std::vector<Voice> voices_;
};

namespace {

thread_local std::string g_ffi_last_error;

void SetFfiLastError(const std::string& message) { g_ffi_last_error = message; }

template <typename Callback>
int32_t WrapFfiCall(Callback&& callback) {
  try {
    callback();
    g_ffi_last_error.clear();
    return 1;
  } catch (const std::exception& error) {
    SetFfiLastError(error.what());
    return 0;
  } catch (...) {
    SetFfiLastError("Unknown FFI error.");
    return 0;
  }
}

class WindowsFfiBridge {
 public:
  int32_t CreateSynth(const SynthSpec& spec) {
    const std::string synth_id = engine_.CreateSynth(spec);
    const int32_t handle = next_handle_++;
    synth_ids_[handle] = synth_id;
    return handle;
  }

  void UpdateSynth(int32_t synth_handle, const SynthSpec& spec) {
    engine_.UpdateSynth(RequireSynthId(synth_handle), spec);
  }

  void TriggerNote(int32_t synth_handle, double frequency_hz, int duration_ms,
                   double velocity, int delay_ms) {
    engine_.TriggerNote(RequireSynthId(synth_handle), frequency_hz, duration_ms,
                        velocity, delay_ms);
  }

  void CancelScheduledNotes(int32_t synth_handle) {
    if (synth_handle < 0) {
      engine_.CancelScheduledNotes(std::nullopt);
      return;
    }
    engine_.CancelScheduledNotes(RequireSynthId(synth_handle));
  }

  void DisposeSynth(int32_t synth_handle) {
    const std::string synth_id = RequireSynthId(synth_handle);
    engine_.DisposeSynth(synth_id);
    synth_ids_.erase(synth_handle);
  }

  void DisposeEngine() {
    engine_.Dispose();
    synth_ids_.clear();
  }

  void Panic() { engine_.Panic(); }

  void Initialize(double master_volume) { engine_.Initialize(master_volume); }

  void SetMasterVolume(double volume) { engine_.SetMasterVolume(volume); }

 private:
  std::string RequireSynthId(int32_t synth_handle) const {
    const auto it = synth_ids_.find(synth_handle);
    if (it == synth_ids_.end()) {
      throw std::runtime_error("Unknown ffi synth handle: " +
                               std::to_string(synth_handle));
    }
    return it->second;
  }

  WindowsSynthKitEngine engine_;
  int32_t next_handle_ = 1;
  std::unordered_map<int32_t, std::string> synth_ids_;
};

WindowsFfiBridge& GetFfiBridge() {
  static WindowsFfiBridge bridge;
  return bridge;
}

}  // namespace

// static
void SynthKitPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<SynthKitPlugin>();
  registrar->AddPlugin(std::move(plugin));
}

SynthKitPlugin::SynthKitPlugin() = default;

SynthKitPlugin::~SynthKitPlugin() = default;

}  // namespace synthkit

extern "C" {

__declspec(dllexport) int32_t synthkit_ffi_is_supported() { return 1; }

__declspec(dllexport) int32_t synthkit_ffi_get_backend_name() {
  synthkit::SetFfiLastError("ffi-windows");
  return 1;
}

__declspec(dllexport) const char* synthkit_ffi_last_error_message() {
  return synthkit::g_ffi_last_error.c_str();
}

__declspec(dllexport) int32_t synthkit_ffi_initialize(double master_volume) {
  return synthkit::WrapFfiCall(
      [&]() { synthkit::GetFfiBridge().Initialize(master_volume); });
}

__declspec(dllexport) void synthkit_ffi_dispose_engine() {
  synthkit::GetFfiBridge().DisposeEngine();
}

__declspec(dllexport) int32_t synthkit_ffi_set_master_volume(double volume) {
  return synthkit::WrapFfiCall(
      [&]() { synthkit::GetFfiBridge().SetMasterVolume(volume); });
}

__declspec(dllexport) int32_t synthkit_ffi_create_synth(
    int32_t waveform, double volume, int32_t attack_ms, int32_t decay_ms,
    double sustain, int32_t release_ms, int32_t filter_enabled,
    double cutoff_hz) {
  int32_t synth_handle = 0;
  const auto spec = synthkit::FfiParseSynthSpec(
      waveform, volume, attack_ms, decay_ms, sustain, release_ms,
      filter_enabled, cutoff_hz);
  const int32_t status = synthkit::WrapFfiCall([&]() {
    synth_handle = synthkit::GetFfiBridge().CreateSynth(spec);
  });
  return status == 1 ? synth_handle : 0;
}

__declspec(dllexport) int32_t synthkit_ffi_update_synth(
    int32_t synth_handle, int32_t waveform, double volume, int32_t attack_ms,
    int32_t decay_ms, double sustain, int32_t release_ms,
    int32_t filter_enabled, double cutoff_hz) {
  const auto spec = synthkit::FfiParseSynthSpec(
      waveform, volume, attack_ms, decay_ms, sustain, release_ms,
      filter_enabled, cutoff_hz);
  return synthkit::WrapFfiCall([&]() {
    synthkit::GetFfiBridge().UpdateSynth(synth_handle, spec);
  });
}

__declspec(dllexport) int32_t synthkit_ffi_trigger_note(
    int32_t synth_handle, double frequency_hz, int32_t duration_ms,
    double velocity, int32_t delay_ms) {
  return synthkit::WrapFfiCall([&]() {
    synthkit::GetFfiBridge().TriggerNote(synth_handle, frequency_hz,
                                         duration_ms, velocity, delay_ms);
  });
}

__declspec(dllexport) int32_t synthkit_ffi_cancel_scheduled_notes(
    int32_t synth_handle) {
  return synthkit::WrapFfiCall([&]() {
    synthkit::GetFfiBridge().CancelScheduledNotes(synth_handle);
  });
}

__declspec(dllexport) int32_t synthkit_ffi_panic() {
  return synthkit::WrapFfiCall([&]() { synthkit::GetFfiBridge().Panic(); });
}

__declspec(dllexport) int32_t synthkit_ffi_dispose_synth(
    int32_t synth_handle) {
  return synthkit::WrapFfiCall([&]() {
    synthkit::GetFfiBridge().DisposeSynth(synth_handle);
  });
}

}
