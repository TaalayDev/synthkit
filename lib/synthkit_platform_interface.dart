import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'synthkit_method_channel.dart';
import 'src/models/synthkit_types.dart';

abstract class SynthKitPlatform extends PlatformInterface {
  SynthKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static SynthKitPlatform _instance = MethodChannelSynthKit();

  static SynthKitPlatform get instance => _instance;

  static set instance(SynthKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String> getBackendName() {
    throw UnimplementedError('getBackendName() has not been implemented.');
  }

  Future<void> initialize({required double masterVolume, String? toneJsUrl}) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<void> disposeEngine() {
    throw UnimplementedError('disposeEngine() has not been implemented.');
  }

  Future<void> setMasterVolume(double volume) {
    throw UnimplementedError('setMasterVolume() has not been implemented.');
  }

  Future<String> createSynth(SynthKitSynthOptions options) {
    throw UnimplementedError('createSynth() has not been implemented.');
  }

  Future<void> updateSynth(String synthId, SynthKitSynthOptions options) {
    throw UnimplementedError('updateSynth() has not been implemented.');
  }

  Future<void> triggerNote({
    required String synthId,
    required double frequencyHz,
    required Duration duration,
    required double velocity,
    Duration delay = Duration.zero,
  }) {
    throw UnimplementedError('triggerNote() has not been implemented.');
  }

  Future<void> cancelScheduledNotes({String? synthId}) {
    throw UnimplementedError(
      'cancelScheduledNotes() has not been implemented.',
    );
  }

  Future<void> panic() {
    throw UnimplementedError('panic() has not been implemented.');
  }

  Future<void> disposeSynth(String synthId) {
    throw UnimplementedError('disposeSynth() has not been implemented.');
  }
}
