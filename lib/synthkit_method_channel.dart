import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'synthkit_platform_interface.dart';
import 'src/ffi/synthkit_ffi_factory.dart';
import 'src/models/synthkit_types.dart';

class MethodChannelSynthKit extends SynthKitPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('synthkit');
  final SynthKitPlatform? _ffiPlatform = createSynthKitFfiPlatform();
  static bool _didLogTransportChoice = false;

  SynthKitPlatform? _resolvedFfiPlatform() {
    final ffiPlatform = _ffiPlatform;
    if (!_didLogTransportChoice) {
      _didLogTransportChoice = true;
      debugPrint(
        ffiPlatform != null
            ? '[synthkit] transport: FFI'
            : '[synthkit] transport: MethodChannel',
      );
    }
    return ffiPlatform;
  }

  bool get _ffiOnlyPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.android => true,
    TargetPlatform.iOS => true,
    TargetPlatform.macOS => true,
    TargetPlatform.windows => true,
    TargetPlatform.linux => true,
    TargetPlatform.fuchsia => false,
  };

  SynthKitPlatform? _resolvePlatformOrThrow() {
    final ffiPlatform = _resolvedFfiPlatform();
    if (ffiPlatform != null) {
      return ffiPlatform;
    }
    if (_ffiOnlyPlatform) {
      throw PlatformException(
        code: 'synthkit/ffi_unavailable',
        message: 'FFI backend is required on this platform but was not loaded.',
      );
    }
    return null;
  }

  @override
  Future<String> getBackendName() async {
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.getBackendName();
    }
    final backend =
        await methodChannel.invokeMethod<String>('getBackendName') ?? 'native';
    return backend;
  }

  @override
  Future<void> initialize({
    required double masterVolume,
    String? toneJsUrl,
  }) async {
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.initialize(
        masterVolume: masterVolume,
        toneJsUrl: toneJsUrl,
      );
    }
    await methodChannel.invokeMethod<void>('initialize', <String, Object?>{
      'masterVolume': masterVolume,
      'toneJsUrl': toneJsUrl,
    });
  }

  @override
  Future<void> disposeEngine() async {
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.disposeEngine();
    }
    await methodChannel.invokeMethod<void>('disposeEngine');
  }

  @override
  Future<void> setMasterVolume(double volume) async {
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.setMasterVolume(volume);
    }
    await methodChannel.invokeMethod<void>('setMasterVolume', <String, Object?>{
      'volume': volume,
    });
  }

  @override
  Future<String> createSynth(SynthKitSynthOptions options) async {
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.createSynth(options);
    }
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
  Future<void> updateSynth(String synthId, SynthKitSynthOptions options) async {
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.updateSynth(synthId, options);
    }
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
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.triggerNote(
        synthId: synthId,
        frequencyHz: frequencyHz,
        duration: duration,
        velocity: velocity,
        delay: delay,
      );
    }
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
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.cancelScheduledNotes(synthId: synthId);
    }
    await methodChannel.invokeMethod<void>(
      'cancelScheduledNotes',
      <String, Object?>{'synthId': synthId},
    );
  }

  @override
  Future<void> panic() async {
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.panic();
    }
    await methodChannel.invokeMethod<void>('panic');
  }

  @override
  Future<void> disposeSynth(String synthId) async {
    final ffiPlatform = _resolvePlatformOrThrow();
    if (ffiPlatform != null) {
      return ffiPlatform.disposeSynth(synthId);
    }
    await methodChannel.invokeMethod<void>('disposeSynth', <String, Object?>{
      'synthId': synthId,
    });
  }
}
