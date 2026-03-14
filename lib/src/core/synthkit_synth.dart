import '../../synthkit_platform_interface.dart';
import '../models/synthkit_note.dart';
import '../models/synthkit_types.dart';
import 'synthkit_engine.dart';

class SynthKitSynth {
  SynthKitSynth.internal(this._engine, this.id, this.options);

  final SynthKitEngine _engine;
  final String id;
  bool _disposed = false;

  SynthKitSynthOptions options;

  Future<void> update(SynthKitSynthOptions nextOptions) async {
    _ensureActive();
    options = nextOptions;
    await SynthKitPlatform.instance.updateSynth(id, nextOptions);
  }

  Future<void> triggerAttackRelease(
    SynthKitNote note,
    Duration duration, {
    double velocity = 1,
    Duration delay = Duration.zero,
  }) async {
    _ensureActive();
    await SynthKitPlatform.instance.triggerNote(
      synthId: id,
      frequencyHz: note.frequencyHz,
      duration: duration,
      velocity: velocity.clamp(0.0, 1.0).toDouble(),
      delay: delay,
    );
  }

  Future<void> cancelScheduledNotes() async {
    if (_disposed) {
      return;
    }
    await SynthKitPlatform.instance.cancelScheduledNotes(synthId: id);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await SynthKitPlatform.instance.cancelScheduledNotes(synthId: id);
    await SynthKitPlatform.instance.disposeSynth(id);
    _disposed = true;
    _engine.unregisterSynth(this);
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('SynthKitSynth $id has already been disposed.');
    }
  }
}
