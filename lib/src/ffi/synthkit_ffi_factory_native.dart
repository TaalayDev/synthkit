import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../synthkit_platform_interface.dart';
import '../models/synthkit_types.dart';

SynthKitPlatform? createSynthKitFfiPlatform() {
  if (kIsWeb) {
    return null;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.linux:
    case TargetPlatform.windows:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _FfiSynthKitPlatform.tryCreate();
    case TargetPlatform.android:
      return _FfiSynthKitPlatform.tryCreate(
        libraryOpener: () => DynamicLibrary.open('libsynthkit_android.so'),
      );
    case TargetPlatform.fuchsia:
      return null;
  }
}

final class _FfiSynthKitPlatform extends SynthKitPlatform {
  _FfiSynthKitPlatform._(this._bindings);

  final _SynthKitBindings _bindings;

  static SynthKitPlatform? tryCreate({
    DynamicLibrary Function()? libraryOpener,
  }) {
    try {
      final bindings = _SynthKitBindings(
        libraryOpener == null ? DynamicLibrary.process() : libraryOpener(),
      );
      if (bindings.isSupported() == 0) {
        return null;
      }
      return _FfiSynthKitPlatform._(bindings);
    } on Object {
      return null;
    }
  }

  @override
  Future<String> getBackendName() async {
    _throwIfFailed(_bindings.backendName(), 'getBackendName');
    return _bindings.readLastString();
  }

  @override
  Future<void> initialize({
    required double masterVolume,
    String? toneJsUrl,
  }) async {
    _throwIfFailed(_bindings.initialize(masterVolume), 'initialize');
  }

  @override
  Future<void> disposeEngine() async {
    _bindings.disposeEngine();
  }

  @override
  Future<void> setMasterVolume(double volume) async {
    _throwIfFailed(_bindings.setMasterVolume(volume), 'setMasterVolume');
  }

  @override
  Future<String> createSynth(SynthKitSynthOptions options) async {
    final handle = _bindings.createSynth(
      options.waveform.index,
      options.volume,
      options.envelope.attack.inMilliseconds,
      options.envelope.decay.inMilliseconds,
      options.envelope.sustain,
      options.envelope.release.inMilliseconds,
      options.filter.enabled ? 1 : 0,
      options.filter.cutoffHz,
    );
    _throwIfFailed(handle, 'createSynth');
    return 'ffi_synth_$handle';
  }

  @override
  Future<void> updateSynth(String synthId, SynthKitSynthOptions options) async {
    _throwIfFailed(
      _bindings.updateSynth(
        _parseSynthHandle(synthId),
        options.waveform.index,
        options.volume,
        options.envelope.attack.inMilliseconds,
        options.envelope.decay.inMilliseconds,
        options.envelope.sustain,
        options.envelope.release.inMilliseconds,
        options.filter.enabled ? 1 : 0,
        options.filter.cutoffHz,
      ),
      'updateSynth',
    );
  }

  @override
  Future<void> triggerNote({
    required String synthId,
    required double frequencyHz,
    required Duration duration,
    required double velocity,
    Duration delay = Duration.zero,
  }) async {
    _throwIfFailed(
      _bindings.triggerNote(
        _parseSynthHandle(synthId),
        frequencyHz,
        duration.inMilliseconds,
        velocity,
        delay.inMilliseconds,
      ),
      'triggerNote',
    );
  }

  @override
  Future<void> cancelScheduledNotes({String? synthId}) async {
    _throwIfFailed(
      _bindings.cancelScheduledNotes(
        synthId == null ? -1 : _parseSynthHandle(synthId),
      ),
      'cancelScheduledNotes',
    );
  }

  @override
  Future<void> panic() async {
    _throwIfFailed(_bindings.panic(), 'panic');
  }

  @override
  Future<void> disposeSynth(String synthId) async {
    _throwIfFailed(
      _bindings.disposeSynth(_parseSynthHandle(synthId)),
      'disposeSynth',
    );
  }

  int _parseSynthHandle(String synthId) {
    const prefix = 'ffi_synth_';
    if (!synthId.startsWith(prefix)) {
      throw PlatformException(
        code: 'synthkit/ffi_invalid_synth_id',
        message: 'Expected an ffi synth id, got "$synthId".',
      );
    }
    final handle = int.tryParse(synthId.substring(prefix.length));
    if (handle == null || handle <= 0) {
      throw PlatformException(
        code: 'synthkit/ffi_invalid_synth_id',
        message: 'Invalid ffi synth id: "$synthId".',
      );
    }
    return handle;
  }

  void _throwIfFailed(int code, String method) {
    if (code > 0) {
      return;
    }
    throw PlatformException(
      code: 'synthkit/ffi_$method',
      message: _bindings.readLastString().ifEmpty(
        'FFI call failed for $method.',
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

final class _SynthKitBindings {
  _SynthKitBindings(DynamicLibrary library)
    : isSupported = library.lookupFunction<_UnaryIntNative, _UnaryIntDart>(
        'synthkit_ffi_is_supported',
      ),
      backendName = library.lookupFunction<_UnaryIntNative, _UnaryIntDart>(
        'synthkit_ffi_get_backend_name',
      ),
      initialize = library.lookupFunction<_InitializeNative, _InitializeDart>(
        'synthkit_ffi_initialize',
      ),
      disposeEngine = library.lookupFunction<_VoidNative, _VoidDart>(
        'synthkit_ffi_dispose_engine',
      ),
      setMasterVolume = library
          .lookupFunction<_SetMasterVolumeNative, _SetMasterVolumeDart>(
            'synthkit_ffi_set_master_volume',
          ),
      createSynth = library
          .lookupFunction<_CreateSynthNative, _CreateSynthDart>(
            'synthkit_ffi_create_synth',
          ),
      updateSynth = library
          .lookupFunction<_UpdateSynthNative, _UpdateSynthDart>(
            'synthkit_ffi_update_synth',
          ),
      triggerNote = library
          .lookupFunction<_TriggerNoteNative, _TriggerNoteDart>(
            'synthkit_ffi_trigger_note',
          ),
      cancelScheduledNotes = library
          .lookupFunction<
            _CancelScheduledNotesNative,
            _CancelScheduledNotesDart
          >('synthkit_ffi_cancel_scheduled_notes'),
      panic = library.lookupFunction<_UnaryIntNative, _UnaryIntDart>(
        'synthkit_ffi_panic',
      ),
      disposeSynth = library
          .lookupFunction<_DisposeSynthNative, _DisposeSynthDart>(
            'synthkit_ffi_dispose_synth',
          ),
      lastErrorMessage = library
          .lookupFunction<_LastErrorMessageNative, _LastErrorMessageDart>(
            'synthkit_ffi_last_error_message',
          );

  final _UnaryIntDart isSupported;
  final _UnaryIntDart backendName;
  final _InitializeDart initialize;
  final _VoidDart disposeEngine;
  final _SetMasterVolumeDart setMasterVolume;
  final _CreateSynthDart createSynth;
  final _UpdateSynthDart updateSynth;
  final _TriggerNoteDart triggerNote;
  final _CancelScheduledNotesDart cancelScheduledNotes;
  final _UnaryIntDart panic;
  final _DisposeSynthDart disposeSynth;
  final _LastErrorMessageDart lastErrorMessage;

  String readLastString() {
    final pointer = lastErrorMessage();
    if (pointer == nullptr) {
      return '';
    }
    return pointer.cast<Utf8>().toDartString();
  }
}

typedef _UnaryIntNative = Int32 Function();
typedef _UnaryIntDart = int Function();

typedef _InitializeNative = Int32 Function(Double);
typedef _InitializeDart = int Function(double);

typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();

typedef _SetMasterVolumeNative = Int32 Function(Double);
typedef _SetMasterVolumeDart = int Function(double);

typedef _CreateSynthNative =
    Int32 Function(Int32, Double, Int32, Int32, Double, Int32, Int32, Double);
typedef _CreateSynthDart =
    int Function(int, double, int, int, double, int, int, double);

typedef _UpdateSynthNative =
    Int32 Function(
      Int32,
      Int32,
      Double,
      Int32,
      Int32,
      Double,
      Int32,
      Int32,
      Double,
    );
typedef _UpdateSynthDart =
    int Function(int, int, double, int, int, double, int, int, double);

typedef _TriggerNoteNative =
    Int32 Function(Int32, Double, Int32, Double, Int32);
typedef _TriggerNoteDart = int Function(int, double, int, double, int);

typedef _CancelScheduledNotesNative = Int32 Function(Int32);
typedef _CancelScheduledNotesDart = int Function(int);

typedef _DisposeSynthNative = Int32 Function(Int32);
typedef _DisposeSynthDart = int Function(int);

typedef _LastErrorMessageNative = Pointer<Char> Function();
typedef _LastErrorMessageDart = Pointer<Char> Function();
