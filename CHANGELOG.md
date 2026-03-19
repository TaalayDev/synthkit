## 0.1.0

- Migrated iOS, macOS, Android, Linux, and Windows native backends to `FFI`.
- Removed old native `MethodChannel` implementations on iOS, macOS, Android,
  Linux, and Windows.
- Added native `FFI` bootstrap for Android via `libsynthkit_android.so`.
- Removed unused `AudioKit` dependency from iOS and macOS podspecs.
- Added transport selection debug logging to help confirm `FFI` vs web backend
  usage at runtime.

## 0.0.1

Initial release of `synthkit`.

- Added a unified Flutter synth API with `SynthKitEngine`, `SynthKitSynth`,
  `SynthKitTransport`, and `SynthKitNote`.
- Added note playback by note name, MIDI note, or raw frequency.
- Added synth configuration with waveform selection, ADSR envelope, per-note
  velocity, and optional low-pass filtering.
- Added beat-based transport scheduling for short musical patterns from Dart.
- Added platform backends for web, iOS, macOS, Android, Linux, and Windows.
- Added automatic Tone.js integration for web and native audio backends for
  Apple, Android, Linux, and Windows platforms.

## 0.0.2

- Small bug fixes and improvements.

## 0.0.3

- Fixed polyphonic synthesis on web platform.

## 0.0.4

- Added a new example app with a complete synth interface.
- Changed the homepage to https://taalaydev.github.io/synthkit/

## 0.0.5

- Added the initial shared `FFI` integration scaffolding and native bindings.
