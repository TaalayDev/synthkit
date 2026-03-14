import '../../synthkit_platform_interface.dart';
import '../models/synthkit_note.dart';
import '../support/synthkit_clock.dart';
import 'synthkit_synth.dart';

class SynthKitTransport {
  SynthKitTransport();

  late SynthKitClock _clock;
  bool _attached = false;
  bool _running = false;
  Duration? _startedAt;
  double _bpm = 120;

  final List<_ScheduledNote> _sequence = <_ScheduledNote>[];

  double get bpm => _bpm;
  bool get isRunning => _running;

  void attach({required SynthKitClock clock, required double bpm}) {
    if (_attached) {
      return;
    }
    _clock = clock;
    _bpm = bpm;
    _attached = true;
  }

  Future<void> setBpm(double bpm) async {
    _ensureAttached();
    if (bpm <= 0) {
      throw ArgumentError.value(bpm, 'bpm', 'BPM must be greater than zero.');
    }
    final elapsedBeats = _running ? _elapsedBeats : 0.0;
    _bpm = bpm;
    if (_running) {
      await SynthKitPlatform.instance.cancelScheduledNotes();
      await _scheduleFromBeat(elapsedBeats);
    }
  }

  Future<void> start() async {
    _ensureAttached();
    if (_running) {
      return;
    }
    _running = true;
    _startedAt = _clock.now();
    await SynthKitPlatform.instance.cancelScheduledNotes();
    await _scheduleFromBeat(0);
  }

  Future<void> stop({bool clearSequence = false}) async {
    if (!_attached) {
      return;
    }
    _running = false;
    _startedAt = null;
    await SynthKitPlatform.instance.cancelScheduledNotes();
    await SynthKitPlatform.instance.panic();
    if (clearSequence) {
      _sequence.clear();
    }
  }

  Future<void> clear() async {
    _sequence.clear();
    await SynthKitPlatform.instance.cancelScheduledNotes();
  }

  Future<void> unscheduleSynth(SynthKitSynth synth) async {
    _sequence.removeWhere((event) => event.synth == synth);
    await SynthKitPlatform.instance.cancelScheduledNotes(synthId: synth.id);
  }

  Future<void> schedule({
    required SynthKitSynth synth,
    required SynthKitNote note,
    required double beat,
    double durationBeats = 1,
    double velocity = 1,
  }) async {
    _ensureAttached();
    if (beat < 0) {
      throw ArgumentError.value(beat, 'beat', 'Beat cannot be negative.');
    }
    if (durationBeats <= 0) {
      throw ArgumentError.value(
        durationBeats,
        'durationBeats',
        'Duration must be greater than zero.',
      );
    }

    final scheduledNote = _ScheduledNote(
      synth: synth,
      note: note,
      beat: beat,
      durationBeats: durationBeats,
      velocity: velocity.clamp(0.0, 1.0).toDouble(),
    );
    _sequence.add(scheduledNote);
    _sequence.sort((left, right) => left.beat.compareTo(right.beat));

    if (_running) {
      final elapsedBeats = _elapsedBeats;
      final beatOffset = beat - elapsedBeats;
      final delay = beatOffset <= 0
          ? Duration.zero
          : _beatsToDuration(beatOffset);
      await synth.triggerAttackRelease(
        note,
        _beatsToDuration(durationBeats),
        velocity: scheduledNote.velocity,
        delay: delay,
      );
    }
  }

  Future<void> _scheduleFromBeat(double elapsedBeats) async {
    for (final note in _sequence) {
      final beatOffset = note.beat - elapsedBeats;
      if (beatOffset < 0) {
        continue;
      }
      await note.synth.triggerAttackRelease(
        note.note,
        _beatsToDuration(note.durationBeats),
        velocity: note.velocity,
        delay: beatOffset == 0 ? Duration.zero : _beatsToDuration(beatOffset),
      );
    }
  }

  Duration _beatsToDuration(double beats) {
    final microsecondsPerBeat = (Duration.microsecondsPerSecond * 60) / _bpm;
    return Duration(microseconds: (beats * microsecondsPerBeat).round());
  }

  double get _elapsedBeats {
    final startedAt = _startedAt;
    if (!_running || startedAt == null) {
      return 0;
    }
    final elapsed = _clock.now() - startedAt;
    return elapsed.inMicroseconds /
        (Duration.microsecondsPerSecond * 60) *
        _bpm;
  }

  void _ensureAttached() {
    if (!_attached) {
      throw StateError('SynthKitTransport is not attached to an engine yet.');
    }
  }
}

class _ScheduledNote {
  const _ScheduledNote({
    required this.synth,
    required this.note,
    required this.beat,
    required this.durationBeats,
    required this.velocity,
  });

  final SynthKitSynth synth;
  final SynthKitNote note;
  final double beat;
  final double durationBeats;
  final double velocity;
}
