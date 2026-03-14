// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'synthkit_platform_interface.dart';
import 'src/models/synthkit_types.dart';

@JS('window')
external JSObject get _window;

class SynthKitWeb extends SynthKitPlatform {
  SynthKitWeb();

  static const String _defaultToneJsUrl =
      'https://cdn.jsdelivr.net/npm/tone@15.1.0/build/Tone.js';

  final Map<String, _WebSynthHandle> _synths = <String, _WebSynthHandle>{};
  final Map<String, List<Timer>> _scheduledTimers = <String, List<Timer>>{};
  Future<void>? _toneLoadFuture;
  JSObject? _masterGain;
  double _masterVolume = 0.8;
  int _nextSynthId = 1;

  static void registerWith(Registrar registrar) {
    SynthKitPlatform.instance = SynthKitWeb();
  }

  @override
  Future<String> getBackendName() async => 'tonejs-web';

  @override
  Future<void> initialize({
    required double masterVolume,
    String? toneJsUrl,
  }) async {
    _masterVolume = masterVolume.clamp(0.0, 1.0).toDouble();
    await _ensureToneLoaded(toneJsUrl ?? _defaultToneJsUrl);
    final tone = _tone;
    if (tone == null) {
      throw StateError('Tone.js did not register a global Tone object.');
    }

    final startPromise = tone.callMethod<JSPromise<JSAny?>>('start'.toJS);
    await startPromise.toDart;

    if (_masterGain == null) {
      final gainCtor = tone.getProperty<JSFunction>('Gain'.toJS);
      final gain = gainCtor.callAsConstructor<JSObject>(_masterVolume.toJS);
      gain.callMethod<JSAny?>('toDestination'.toJS);
      _masterGain = gain;
    } else {
      _setGainValue(_masterGain!, _masterVolume);
    }
  }

  @override
  Future<void> disposeEngine() async {
    await cancelScheduledNotes();
    await panic();
    for (final synthId in _synths.keys.toList()) {
      await disposeSynth(synthId);
    }
    final masterGain = _masterGain;
    if (masterGain != null) {
      masterGain.callMethod<JSAny?>('dispose'.toJS);
      _masterGain = null;
    }
  }

  @override
  Future<void> setMasterVolume(double volume) async {
    _masterVolume = volume.clamp(0.0, 1.0).toDouble();
    final masterGain = _masterGain;
    if (masterGain != null) {
      _setGainValue(masterGain, _masterVolume);
    }
  }

  @override
  Future<String> createSynth(SynthKitSynthOptions options) async {
    await _ensureInitialized();
    final tone = _tone!;
    final synthCtor = tone.getProperty<JSFunction>('Synth'.toJS);
    final synth = synthCtor.callAsConstructor<JSObject>(_synthOptions(options));

    final gainCtor = tone.getProperty<JSFunction>('Gain'.toJS);
    final gain = gainCtor.callAsConstructor<JSObject>(options.volume.toJS);
    JSObject? filter;
    if (options.filter.enabled) {
      final filterCtor = tone.getProperty<JSFunction>('Filter'.toJS);
      filter = filterCtor.callAsConstructor<JSObject>(
        options.filter.cutoffHz.toJS,
        'lowpass'.toJS,
      );
      synth.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[filter]);
      filter.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[gain]);
    } else {
      synth.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[gain]);
    }
    gain.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[_masterGain]);

    final synthId = 'web_synth_${_nextSynthId++}';
    _synths[synthId] = _WebSynthHandle(
      synth: synth,
      gain: gain,
      filter: filter,
      options: options,
    );
    return synthId;
  }

  @override
  Future<void> updateSynth(
    String synthId,
    SynthKitSynthOptions options,
  ) async {
    final synth = _requireSynth(synthId);
    final oscillator = synth.synth.getProperty<JSObject>('oscillator'.toJS);
    oscillator.setProperty('type'.toJS, options.waveform.wireName.toJS);

    final envelope = synth.synth.getProperty<JSObject>('envelope'.toJS);
    for (final entry in options.envelope.toToneMap().entries) {
      envelope.setProperty(
        entry.key.toJS,
        (entry.value as num).toDouble().toJS,
      );
    }

    _setGainValue(synth.gain, options.volume);

    if (options.filter.enabled) {
      final filter = synth.filter;
      if (filter == null) {
        final tone = _tone!;
        final filterCtor = tone.getProperty<JSFunction>('Filter'.toJS);
        final newFilter = filterCtor.callAsConstructor<JSObject>(
          options.filter.cutoffHz.toJS,
          'lowpass'.toJS,
        );
        synth.synth.callMethod<JSAny?>('disconnect'.toJS);
        synth.gain.callMethod<JSAny?>('disconnect'.toJS);
        synth.synth.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[
          newFilter,
        ]);
        newFilter.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[
          synth.gain,
        ]);
        synth.gain.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[
          _masterGain,
        ]);
        synth.filter = newFilter;
      } else {
        filter.setProperty('type'.toJS, 'lowpass'.toJS);
        final frequency = filter.getProperty<JSObject>('frequency'.toJS);
        frequency.setProperty('value'.toJS, options.filter.cutoffHz.toJS);
      }
    } else if (synth.filter != null) {
      synth.synth.callMethod<JSAny?>('disconnect'.toJS);
      synth.filter!.callMethod<JSAny?>('disconnect'.toJS);
      synth.synth.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[
        synth.gain,
      ]);
      synth.gain.callMethodVarArgs<JSAny?>('connect'.toJS, <JSAny?>[
        _masterGain,
      ]);
      synth.filter!.callMethod<JSAny?>('dispose'.toJS);
      synth.filter = null;
    }

    synth.options = options;
  }

  @override
  Future<void> triggerNote({
    required String synthId,
    required double frequencyHz,
    required Duration duration,
    required double velocity,
    Duration delay = Duration.zero,
  }) async {
    final synth = _requireSynth(synthId);
    void playNow() {
      synth.synth
          .callMethodVarArgs<JSAny?>('triggerAttackRelease'.toJS, <JSAny?>[
            frequencyHz.toJS,
            (duration.inMicroseconds / Duration.microsecondsPerSecond).toJS,
            _tone!.callMethod<JSAny?>('now'.toJS),
            velocity.clamp(0.0, 1.0).toDouble().toJS,
          ]);
    }

    if (delay <= Duration.zero) {
      playNow();
      return;
    }

    final timer = Timer(delay, playNow);
    _scheduledTimers.putIfAbsent(synthId, () => <Timer>[]).add(timer);
  }

  @override
  Future<void> cancelScheduledNotes({String? synthId}) async {
    if (synthId != null) {
      final timers = _scheduledTimers.remove(synthId) ?? const <Timer>[];
      for (final timer in timers) {
        timer.cancel();
      }
      return;
    }

    for (final timers in _scheduledTimers.values) {
      for (final timer in timers) {
        timer.cancel();
      }
    }
    _scheduledTimers.clear();
  }

  @override
  Future<void> panic() async {
    final tone = _tone;
    if (tone == null) {
      return;
    }
    final now = tone.callMethod<JSAny?>('now'.toJS);
    for (final synth in _synths.values) {
      synth.synth.callMethodVarArgs<JSAny?>('triggerRelease'.toJS, <JSAny?>[
        now,
      ]);
    }
  }

  @override
  Future<void> disposeSynth(String synthId) async {
    await cancelScheduledNotes(synthId: synthId);
    final synth = _synths.remove(synthId);
    if (synth == null) {
      return;
    }
    synth.synth.callMethod<JSAny?>('dispose'.toJS);
    synth.gain.callMethod<JSAny?>('dispose'.toJS);
    synth.filter?.callMethod<JSAny?>('dispose'.toJS);
  }

  Future<void> _ensureInitialized() async {
    if (_masterGain == null) {
      await initialize(masterVolume: _masterVolume, toneJsUrl: null);
    }
  }

  Future<void> _ensureToneLoaded(String url) {
    return _toneLoadFuture ??= _loadToneScript(url);
  }

  Future<void> _loadToneScript(String url) async {
    if (_tone != null) {
      return;
    }
    final completer = Completer<void>();
    final script = html.ScriptElement()
      ..src = url
      ..defer = true
      ..type = 'text/javascript';
    script.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Failed to load Tone.js from $url.'),
        );
      }
    });
    script.onLoad.first.then((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    html.document.head?.append(script);
    await completer.future;
  }

  JSObject? get _tone {
    final tone = _window['Tone'];
    if (tone == null) {
      return null;
    }
    return tone as JSObject;
  }

  _WebSynthHandle _requireSynth(String synthId) {
    final synth = _synths[synthId];
    if (synth == null) {
      throw StateError('Unknown synth id: $synthId');
    }
    return synth;
  }

  void _setGainValue(JSObject gainNode, double value) {
    final gain = gainNode.getProperty<JSObject>('gain'.toJS);
    gain.setProperty('value'.toJS, value.toJS);
  }

  JSObject _synthOptions(SynthKitSynthOptions options) {
    final oscillator = _newObject()
      ..setProperty('type'.toJS, options.waveform.wireName.toJS);
    final envelope = _newObject();
    for (final entry in options.envelope.toToneMap().entries) {
      envelope.setProperty(
        entry.key.toJS,
        (entry.value as num).toDouble().toJS,
      );
    }
    return _newObject()
      ..setProperty('oscillator'.toJS, oscillator)
      ..setProperty('envelope'.toJS, envelope);
  }

  JSObject _newObject() {
    final objectCtor = _window.getProperty<JSFunction>('Object'.toJS);
    return objectCtor.callAsConstructor<JSObject>();
  }
}

class _WebSynthHandle {
  _WebSynthHandle({
    required this.synth,
    required this.gain,
    required this.filter,
    required this.options,
  });

  final JSObject synth;
  final JSObject gain;
  JSObject? filter;
  SynthKitSynthOptions options;
}
