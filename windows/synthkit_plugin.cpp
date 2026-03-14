#include "synthkit_plugin.h"

#include <windows.h>
#include <mmsystem.h>

#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

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

using flutter::EncodableMap;
using flutter::EncodableValue;

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

const EncodableMap* GetMap(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return nullptr;
  }
  return std::get_if<EncodableMap>(&it->second);
}

std::optional<std::string> GetString(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return std::nullopt;
}

double GetDouble(const EncodableMap& map, const char* key, double fallback) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<double>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return static_cast<double>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*value);
  }
  return fallback;
}

int GetInt(const EncodableMap& map, const char* key, int fallback) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  if (const auto* value = std::get_if<double>(&it->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

bool GetBool(const EncodableMap& map, const char* key, bool fallback) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(&it->second)) {
    return *value;
  }
  return fallback;
}

SynthSpec ParseSynthSpec(const EncodableMap& args) {
  SynthSpec spec;
  spec.waveform = GetString(args, "waveform").value_or("sine");
  spec.volume = GetDouble(args, "volume", 0.8);
  if (const auto* envelope = GetMap(args, "envelope")) {
    spec.envelope.attack_ms = GetInt(*envelope, "attackMs", 10);
    spec.envelope.decay_ms = GetInt(*envelope, "decayMs", 120);
    spec.envelope.sustain = GetDouble(*envelope, "sustain", 0.75);
    spec.envelope.release_ms = GetInt(*envelope, "releaseMs", 240);
  }
  if (const auto* filter = GetMap(args, "filter")) {
    spec.filter.enabled = GetBool(*filter, "enabled", false);
    spec.filter.cutoff_hz = GetDouble(*filter, "cutoffHz", 1800.0);
  }
  return spec;
}

std::string RequireString(const EncodableMap& map, const char* key) {
  const auto value = GetString(map, key);
  if (!value.has_value() || value->empty()) {
    throw std::runtime_error(std::string("Missing ") + key + ".");
  }
  return *value;
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

// static
void SynthKitPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "synthkit",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SynthKitPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

SynthKitPlugin::SynthKitPlugin()
    : engine_(std::make_unique<WindowsSynthKitEngine>()) {}

SynthKitPlugin::~SynthKitPlugin() = default;

void SynthKitPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  try {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());

    if (method_call.method_name() == "getBackendName") {
      result->Success(EncodableValue("native-windows"));
      return;
    }

    if (method_call.method_name() == "initialize") {
      if (args == nullptr) {
        throw std::runtime_error("Expected an argument map.");
      }
      engine_->Initialize(GetDouble(*args, "masterVolume", 0.8));
      result->Success();
      return;
    }

    if (method_call.method_name() == "disposeEngine") {
      engine_->Dispose();
      result->Success();
      return;
    }

    if (method_call.method_name() == "setMasterVolume") {
      if (args == nullptr) {
        throw std::runtime_error("Expected an argument map.");
      }
      engine_->SetMasterVolume(GetDouble(*args, "volume", 0.8));
      result->Success();
      return;
    }

    if (method_call.method_name() == "createSynth") {
      if (args == nullptr) {
        throw std::runtime_error("Expected a synth config map.");
      }
      result->Success(EncodableValue(engine_->CreateSynth(ParseSynthSpec(*args))));
      return;
    }

    if (method_call.method_name() == "updateSynth") {
      if (args == nullptr) {
        throw std::runtime_error("Expected a synth config map.");
      }
      engine_->UpdateSynth(RequireString(*args, "synthId"),
                           ParseSynthSpec(*args));
      result->Success();
      return;
    }

    if (method_call.method_name() == "triggerNote") {
      if (args == nullptr) {
        throw std::runtime_error("Expected a trigger note map.");
      }
      engine_->TriggerNote(RequireString(*args, "synthId"),
                           GetDouble(*args, "frequencyHz", 440.0),
                           GetInt(*args, "durationMs", 500),
                           GetDouble(*args, "velocity", 1.0),
                           GetInt(*args, "delayMs", 0));
      result->Success();
      return;
    }

    if (method_call.method_name() == "cancelScheduledNotes") {
      if (args != nullptr) {
        engine_->CancelScheduledNotes(GetString(*args, "synthId"));
      } else {
        engine_->CancelScheduledNotes(std::nullopt);
      }
      result->Success();
      return;
    }

    if (method_call.method_name() == "panic") {
      engine_->Panic();
      result->Success();
      return;
    }

    if (method_call.method_name() == "disposeSynth") {
      if (args == nullptr) {
        throw std::runtime_error("Expected a synth id map.");
      }
      engine_->DisposeSynth(RequireString(*args, "synthId"));
      result->Success();
      return;
    }

    result->NotImplemented();
  } catch (const std::exception& error) {
    result->Error("synthkit/error", error.what());
  }
}

}  // namespace synthkit
