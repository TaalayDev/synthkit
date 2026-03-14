## 0.0.1

Initial release of `synthkit`.

- Added a unified Flutter synth API with `SynthKitEngine`, `SynthKitSynth`,
  `SynthKitTransport`, and `SynthKitNote`.
- Added note playback by note name, MIDI note, or raw frequency.
- Added synth configuration with waveform selection, ADSR envelope, per-note
  velocity, and optional low-pass filtering.
- Added beat-based transport scheduling for short musical patterns from Dart.
- Added platform backends for web, iOS, macOS, Android, and Windows.
- Added automatic Tone.js integration for web and native audio backends for
  Apple, Android, and Windows platforms.
