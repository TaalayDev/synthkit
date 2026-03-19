# synthkit

`synthkit` is a synth-first Flutter plugin for musical note playback and
simple beat-based scheduling across Flutter platforms.

It gives you one Dart API for:

- creating synths
- configuring waveform, ADSR envelope, and low-pass filtering
- triggering notes by note name, MIDI note, or raw frequency
- scheduling short patterns in beat time

The API is intentionally small. It is designed for metronomes, ear-training
apps, music toys, UI sound prototypes, and lightweight sequencer-style
interfaces.

Hosted example: [taalaydev.github.io/synthkit](https://taalaydev.github.io/synthkit/)

## Platform support

| Platform | Supported | Backend |
| --- | --- | --- |
| Web | Yes | Tone.js loaded at runtime |
| iOS | Yes | `FFI` + native `AVAudioEngine` synth |
| macOS | Yes | `FFI` + native `AVAudioEngine` synth |
| Android | Yes | `FFI` + native `AudioTrack` synth |
| Windows | Yes | `FFI` + native `waveOut` synth |
| Linux | Yes | `FFI` + native ALSA synth |

## Features

- Unified `SynthKitEngine`, `SynthKitSynth`, and `SynthKitTransport` API.
- `sine`, `square`, `triangle`, and `sawtooth` waveforms.
- ADSR envelope per synth.
- Optional low-pass filter per synth.
- Per-note velocity and delayed triggering.
- Beat-based transport for scheduling note sequences from Dart.
- Automatic Tone.js bootstrap on web.
- `FFI` native backends for mobile and desktop.

## Installation

Add the package to your app:

```yaml
dependencies:
  synthkit: ^0.1.0
```

Then install dependencies:

```bash
flutter pub get
```

No extra platform setup is required for iOS, macOS, Windows, or web beyond
normal Flutter plugin integration.

Android builds now include a native `FFI` library via the Android NDK.
Make sure your Android toolchain can build CMake-based native targets.

For Linux builds, install ALSA development headers first. On Debian or Ubuntu:

```bash
sudo apt install libasound2-dev
```

When debugging backend selection, `synthkit` logs the chosen transport once at
startup:

- `[synthkit] transport: FFI`
- `[synthkit] transport: MethodChannel`

## Quick start

```dart
import 'package:synthkit/synthkit.dart';

final engine = SynthKitEngine();

await engine.initialize(
  bpm: 112,
  masterVolume: 0.7,
);

final synth = await engine.createSynth(
  const SynthKitSynthOptions(
    waveform: SynthKitWaveform.sawtooth,
    envelope: SynthKitEnvelope(
      attack: Duration(milliseconds: 8),
      decay: Duration(milliseconds: 140),
      sustain: 0.65,
      release: Duration(milliseconds: 260),
    ),
    filter: SynthKitFilter.lowPass(cutoffHz: 1600),
    volume: 0.75,
  ),
);

await synth.triggerAttackRelease(
  SynthKitNote.parse('C4'),
  const Duration(milliseconds: 380),
);
```

## Recommended lifecycle

In most apps the flow looks like this:

1. Create one `SynthKitEngine`.
2. Call `initialize()` once before creating synths.
3. Create one or more synths with `createSynth()`.
4. Trigger notes directly or schedule them with `transport`.
5. Dispose the engine when the owning widget or service is destroyed.

Example:

```dart
class _ExampleState extends State<Example> {
  final SynthKitEngine _engine = SynthKitEngine();
  SynthKitSynth? _synth;

  Future<void> initializeAudio() async {
    await _engine.initialize(bpm: 120, masterVolume: 0.8);
    _synth ??= await _engine.createSynth();
  }

  Future<void> playA4() async {
    await initializeAudio();
    await _synth!.triggerAttackRelease(
      SynthKitNote.parse('A4'),
      const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}
```

## Core API

### `SynthKitEngine`

Main entry point for audio.

```dart
final engine = SynthKitEngine();
```

Important members:

- `initialize({double bpm = 120, double masterVolume = 0.8, String? webToneJsUrl})`
  Initializes the platform backend and attaches the transport.
- `createSynth([SynthKitSynthOptions options])`
  Creates a synth on the active backend.
- `setMasterVolume(double volume)`
  Sets the global output volume from `0.0` to `1.0`.
- `backendName`
  Returns a backend identifier such as `tonejs-web`, `ffi-ios`,
  `ffi-macos`, `ffi-android`, `ffi-linux`, or `ffi-windows`.
- `transport`
  Beat-based scheduler for short sequences.
- `dispose()`
  Stops transport playback, disposes synths, and tears down the backend.

Notes:

- `initialize()` must be awaited before `createSynth()` or
  `setMasterVolume()`.
- Calling `initialize()` more than once is safe; subsequent calls are ignored.
- `dispose()` is idempotent.

### `SynthKitSynth`

Represents a synth instance created by the engine.

```dart
final synth = await engine.createSynth();
```

Important members:

- `update(SynthKitSynthOptions nextOptions)`
  Reconfigures the synth waveform, envelope, filter, and volume.
- `triggerAttackRelease(SynthKitNote note, Duration duration, {double velocity = 1, Duration delay = Duration.zero})`
  Plays a note immediately or after a delay.
- `cancelScheduledNotes()`
  Cancels queued delayed notes for that synth.
- `dispose()`
  Disposes the synth and releases its native or web resources.

### `SynthKitTransport`

Schedules notes in beat time from Dart.

```dart
await engine.transport.schedule(
  synth: synth,
  note: SynthKitNote.parse('C4'),
  beat: 0,
  durationBeats: 0.5,
);
await engine.transport.start();
```

Important members:

- `schedule(...)`
  Adds a note event to the transport sequence.
- `start()`
  Starts playback of the scheduled sequence.
- `stop({bool clearSequence = false})`
  Stops playback, clears active notes, and optionally removes the sequence.
- `setBpm(double bpm)`
  Changes transport tempo. If transport is already running, remaining notes are
  rescheduled at the new BPM.
- `clear()`
  Removes all scheduled note events.
- `unscheduleSynth(SynthKitSynth synth)`
  Removes all events for a given synth.
- `bpm`
  Current BPM value.
- `isRunning`
  Whether the transport is currently active.

Notes:

- The transport is a one-shot scheduler. It does not loop automatically.
- Scheduling is managed from Dart, not from a native sequencer.
- `SynthKitEngine.initialize()` attaches the transport for you.

### `SynthKitNote`

You can construct notes in three ways:

```dart
final byName = SynthKitNote.parse('C#4');
final byMidi = SynthKitNote.midi(69); // A4
final byFrequency = SynthKitNote.frequency(440.0);
```

Supported note-name format:

- note letter `A` through `G`
- optional `#` or `b`
- octave number, including negative octaves

Examples:

- `C4`
- `Bb3`
- `F#5`

## Synth configuration

Use `SynthKitSynthOptions` to configure a synth:

```dart
const SynthKitSynthOptions(
  waveform: SynthKitWaveform.square,
  envelope: SynthKitEnvelope(
    attack: Duration(milliseconds: 20),
    decay: Duration(milliseconds: 100),
    sustain: 0.5,
    release: Duration(milliseconds: 200),
  ),
  filter: SynthKitFilter.lowPass(cutoffHz: 1200),
  volume: 0.7,
)
```

### Defaults

| Setting | Default |
| --- | --- |
| `waveform` | `SynthKitWaveform.sine` |
| `envelope.attack` | `10ms` |
| `envelope.decay` | `120ms` |
| `envelope.sustain` | `0.75` |
| `envelope.release` | `240ms` |
| `filter` | `SynthKitFilter.disabled()` |
| `volume` | `0.8` |

### Waveforms

Supported waveforms:

- `SynthKitWaveform.sine`
- `SynthKitWaveform.square`
- `SynthKitWaveform.triangle`
- `SynthKitWaveform.sawtooth`

### Envelope

`SynthKitEnvelope` models a standard ADSR envelope:

- `attack`
- `decay`
- `sustain`
- `release`

### Filter

`SynthKitFilter` currently supports:

- `SynthKitFilter.disabled()`
- `SynthKitFilter.lowPass(cutoffHz: ...)`

## Scheduling a pattern

This schedules a short four-beat phrase:

```dart
await engine.transport.setBpm(112);

await engine.transport.schedule(
  synth: synth,
  note: SynthKitNote.parse('A3'),
  beat: 0,
  durationBeats: 0.5,
);
await engine.transport.schedule(
  synth: synth,
  note: SynthKitNote.parse('C4'),
  beat: 1,
  durationBeats: 0.5,
);
await engine.transport.schedule(
  synth: synth,
  note: SynthKitNote.parse('E4'),
  beat: 2,
  durationBeats: 0.5,
);
await engine.transport.schedule(
  synth: synth,
  note: SynthKitNote.parse('G4'),
  beat: 3,
  durationBeats: 1,
);

await engine.transport.start();
```

To stop and clear the scheduled pattern:

```dart
await engine.transport.stop(clearSequence: true);
```

## Web usage

On web, `synthkit` loads Tone.js automatically the first time you initialize
the engine.

Default Tone.js URL:

```text
https://cdn.jsdelivr.net/npm/tone@15.1.0/build/Tone.js
```

If you want to self-host Tone.js or use a different CDN, pass a custom URL:

```dart
await engine.initialize(
  bpm: 120,
  masterVolume: 0.8,
  webToneJsUrl: 'https://your-cdn.example.com/Tone.js',
);
```

Important web note:

- Browser audio usually must be unlocked from a user gesture. In practice, call
  `initialize()` from a button tap or another direct user interaction.

## Platform notes

### iOS and macOS

- Uses a native `AVAudioEngine`-based synth backend.
- No additional manual setup is required in a standard Flutter app.

### Android

- Uses a native `AudioTrack`-based synth backend.
- Good fit for lightweight synthesis and UI sound playback.

### Windows

- Uses a native `waveOut` backend.
- Best suited to simple synthesis and note triggering.

### Linux

- Uses a native ALSA PCM playback backend.
- Requires ALSA development headers when building the Linux app or example.

### Backend differences

The public Dart API is shared, but exact sound character can vary by backend.
This is expected because each platform uses its own underlying audio engine.

## Error handling and best practices

- Always await `initialize()` before using the engine.
- Dispose the engine when you no longer need audio resources.
- Keep `masterVolume`, synth `volume`, and note `velocity` in the `0.0` to
  `1.0` range.
- On web, initialize from a user gesture.
- For long-running or advanced sequencing needs, treat the current transport as
  a lightweight musical scheduler rather than a DAW-style timeline.

## Current limitations

`synthkit` is intentionally narrow today. It does not currently provide:

- audio file playback or sampling
- MIDI input or output
- recording or offline rendering
- effect chains beyond a simple low-pass filter
- looped transport playback

## Example app

The package includes a runnable Flutter example in
[`example/`](example) that demonstrates:

- initializing the engine
- creating a synth
- playing a one-shot note
- scheduling a short beat-based pattern
- stopping playback

You can also try the hosted web example here:
[taalaydev.github.io/synthkit](https://taalaydev.github.io/synthkit/)

Run it with:

```bash
cd example
flutter run
```

## Verification

This package has been verified in this workspace with:

- `flutter analyze`
- `flutter build macos --debug`
- `flutter build ios --simulator --debug --no-codesign`
- `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/initialize_test.dart -d macos`
- `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/initialize_test.dart -d <ios-simulator-id>`
