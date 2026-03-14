import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'synthkit_platform_interface.dart';
import 'src/models/synthkit_types.dart';

class MethodChannelSynthKit extends SynthKitPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('synthkit');

  @override
  Future<String> getBackendName() async {
    final backend =
        await methodChannel.invokeMethod<String>('getBackendName') ?? 'native';
    return backend;
  }

  @override
  Future<void> initialize({
    required double masterVolume,
    String? toneJsUrl,
  }) async {
    await methodChannel.invokeMethod<void>('initialize', <String, Object?>{
      'masterVolume': masterVolume,
      'toneJsUrl': toneJsUrl,
    });
  }

  @override
  Future<void> disposeEngine() async {
    await methodChannel.invokeMethod<void>('disposeEngine');
  }

  @override
  Future<void> setMasterVolume(double volume) async {
    await methodChannel.invokeMethod<void>('setMasterVolume', <String, Object?>{
      'volume': volume,
    });
  }

  @override
  Future<String> createSynth(SynthKitSynthOptions options) async {
    final synthId = await methodChannel.invokeMethod<String>(
      'createSynth',
      options.toMap(),
    );
    if (synthId == null || synthId.isEmpty) {
      throw PlatformException(
        code: 'synthkit/no_synth_id',
        message: 'Native backend did not return a synth id.',
      );
    }
    return synthId;
  }

  @override
  Future<void> updateSynth(
    String synthId,
    SynthKitSynthOptions options,
  ) async {
    await methodChannel.invokeMethod<void>('updateSynth', <String, Object?>{
      'synthId': synthId,
      ...options.toMap(),
    });
  }

  @override
  Future<void> triggerNote({
    required String synthId,
    required double frequencyHz,
    required Duration duration,
    required double velocity,
    Duration delay = Duration.zero,
  }) async {
    await methodChannel.invokeMethod<void>('triggerNote', <String, Object?>{
      'synthId': synthId,
      'frequencyHz': frequencyHz,
      'durationMs': duration.inMilliseconds,
      'velocity': velocity,
      'delayMs': delay.inMilliseconds,
    });
  }

  @override
  Future<void> cancelScheduledNotes({String? synthId}) async {
    await methodChannel.invokeMethod<void>(
      'cancelScheduledNotes',
      <String, Object?>{'synthId': synthId},
    );
  }

  @override
  Future<void> panic() async {
    await methodChannel.invokeMethod<void>('panic');
  }

  @override
  Future<void> disposeSynth(String synthId) async {
    await methodChannel.invokeMethod<void>('disposeSynth', <String, Object?>{
      'synthId': synthId,
    });
  }
}
