import 'dart:math' as math;

class SynthKitNote {
  const SynthKitNote._({
    required this.frequencyHz,
    required this.label,
    this.midi,
  });

  factory SynthKitNote.frequency(double frequencyHz, {String? label}) {
    if (frequencyHz <= 0) {
      throw ArgumentError.value(
        frequencyHz,
        'frequencyHz',
        'Frequency must be greater than zero.',
      );
    }
    return SynthKitNote._(
      frequencyHz: frequencyHz,
      label: label ?? '${frequencyHz.toStringAsFixed(2)}Hz',
    );
  }

  factory SynthKitNote.midi(int midi) {
    if (midi < 0 || midi > 127) {
      throw ArgumentError.value(midi, 'midi', 'MIDI note must be 0-127.');
    }
    return SynthKitNote._(
      frequencyHz: _midiToFrequency(midi),
      label: _midiToLabel(midi),
      midi: midi,
    );
  }

  factory SynthKitNote.parse(String input) {
    final match = RegExp(
      r'^([A-Ga-g])([#b]?)(-?\d+)$',
    ).firstMatch(input.trim());
    if (match == null) {
      throw FormatException('Invalid note name: $input');
    }
    final note = match.group(1)!.toUpperCase();
    final accidental = match.group(2)!;
    final octave = int.parse(match.group(3)!);
    final semitone = switch ('$note$accidental') {
      'C' => 0,
      'C#' => 1,
      'DB' => 1,
      'D' => 2,
      'D#' => 3,
      'EB' => 3,
      'E' => 4,
      'F' => 5,
      'F#' => 6,
      'GB' => 6,
      'G' => 7,
      'G#' => 8,
      'AB' => 8,
      'A' => 9,
      'A#' => 10,
      'BB' => 10,
      'B' => 11,
      _ => throw FormatException('Invalid note name: $input'),
    };
    final midi = (octave + 1) * 12 + semitone;
    return SynthKitNote.midi(midi);
  }

  final double frequencyHz;
  final String label;
  final int? midi;

  static double _midiToFrequency(int midi) {
    return 440.0 * math.pow(2, (midi - 69) / 12.0).toDouble();
  }

  static String _midiToLabel(int midi) {
    const names = <String>[
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final octave = (midi ~/ 12) - 1;
    return '${names[midi % 12]}$octave';
  }
}
