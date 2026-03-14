import 'package:flutter/foundation.dart';

enum SynthKitWaveform { sine, square, triangle, sawtooth }

extension SynthKitWaveformName on SynthKitWaveform {
  String get wireName => switch (this) {
    SynthKitWaveform.sine => 'sine',
    SynthKitWaveform.square => 'square',
    SynthKitWaveform.triangle => 'triangle',
    SynthKitWaveform.sawtooth => 'sawtooth',
  };
}

@immutable
class SynthKitEnvelope {
  const SynthKitEnvelope({
    this.attack = const Duration(milliseconds: 10),
    this.decay = const Duration(milliseconds: 120),
    this.sustain = 0.75,
    this.release = const Duration(milliseconds: 240),
  }) : assert(sustain >= 0 && sustain <= 1);

  final Duration attack;
  final Duration decay;
  final double sustain;
  final Duration release;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'attackMs': attack.inMilliseconds,
      'decayMs': decay.inMilliseconds,
      'sustain': sustain,
      'releaseMs': release.inMilliseconds,
    };
  }

  Map<String, Object?> toToneMap() {
    return <String, Object?>{
      'attack': attack.inMicroseconds / Duration.microsecondsPerSecond,
      'decay': decay.inMicroseconds / Duration.microsecondsPerSecond,
      'sustain': sustain,
      'release': release.inMicroseconds / Duration.microsecondsPerSecond,
    };
  }
}

@immutable
class SynthKitFilter {
  const SynthKitFilter.lowPass({this.cutoffHz = 1800})
    : enabled = true,
      assert(cutoffHz > 0);

  const SynthKitFilter.disabled() : enabled = false, cutoffHz = 1800;

  final bool enabled;
  final double cutoffHz;

  Map<String, Object?> toMap() {
    return <String, Object?>{'enabled': enabled, 'cutoffHz': cutoffHz};
  }
}

@immutable
class SynthKitSynthOptions {
  const SynthKitSynthOptions({
    this.waveform = SynthKitWaveform.sine,
    this.envelope = const SynthKitEnvelope(),
    this.filter = const SynthKitFilter.disabled(),
    this.volume = 0.8,
  }) : assert(volume >= 0 && volume <= 1);

  final SynthKitWaveform waveform;
  final SynthKitEnvelope envelope;
  final SynthKitFilter filter;
  final double volume;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'waveform': waveform.wireName,
      'volume': volume,
      'envelope': envelope.toMap(),
      'filter': filter.toMap(),
    };
  }
}
