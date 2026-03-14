import '../../synthkit_platform_interface.dart';
import '../models/synthkit_types.dart';
import '../support/synthkit_clock.dart';
import 'synthkit_synth.dart';
import 'synthkit_transport.dart';

class SynthKitEngine {
  SynthKitEngine({SynthKitClock? clock})
    : _clock = clock ?? SystemSynthKitClock(),
      transport = SynthKitTransport();

  final SynthKitClock _clock;
  final Set<SynthKitSynth> _synths = <SynthKitSynth>{};
  bool _initialized = false;
  bool _disposed = false;

  double _masterVolume = 0.8;

  late final SynthKitTransport transport;

  Future<void> initialize({
    double bpm = 120,
    double masterVolume = 0.8,
    String? webToneJsUrl,
  }) async {
    _throwIfDisposed();
    if (_initialized) {
      return;
    }
    _masterVolume = masterVolume.clamp(0.0, 1.0).toDouble();
    await SynthKitPlatform.instance.initialize(
      masterVolume: _masterVolume,
      toneJsUrl: webToneJsUrl,
    );
    transport.attach(clock: _clock, bpm: bpm);
    _initialized = true;
  }

  Future<String> get backendName async {
    return SynthKitPlatform.instance.getBackendName();
  }

  double get masterVolume => _masterVolume;

  Future<void> setMasterVolume(double volume) async {
    _ensureInitialized();
    _masterVolume = volume.clamp(0.0, 1.0).toDouble();
    await SynthKitPlatform.instance.setMasterVolume(_masterVolume);
  }

  Future<SynthKitSynth> createSynth([
    SynthKitSynthOptions options = const SynthKitSynthOptions(),
  ]) async {
    _ensureInitialized();
    final synthId = await SynthKitPlatform.instance.createSynth(options);
    final synth = SynthKitSynth.internal(this, synthId, options);
    _synths.add(synth);
    return synth;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await transport.stop(clearSequence: true);
    for (final synth in _synths.toList()) {
      await synth.dispose();
    }
    await SynthKitPlatform.instance.disposeEngine();
    _synths.clear();
    _disposed = true;
  }

  void unregisterSynth(SynthKitSynth synth) {
    _synths.remove(synth);
  }

  void _ensureInitialized() {
    _throwIfDisposed();
    if (!_initialized) {
      throw StateError('SynthKitEngine.initialize() must be awaited first.');
    }
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('SynthKitEngine has already been disposed.');
    }
  }
}
