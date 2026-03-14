import 'package:synthkit/synthkit.dart';
import 'package:synthkit/synthkit_platform_interface.dart';
import 'package:synthkit/synthkit_method_channel.dart';
import 'package:synthkit/src/support/synthkit_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeSynthKitPlatform
    with MockPlatformInterfaceMixin
    implements SynthKitPlatform {
  bool initialized = false;
  final List<TriggeredNote> triggeredNotes = <TriggeredNote>[];
  double masterVolume = 0.8;
  int synthCount = 0;

  @override
  Future<void> cancelScheduledNotes({String? synthId}) async {}

  @override
  Future<String> createSynth(SynthKitSynthOptions options) async {
    synthCount += 1;
    return 'fake_synth_$synthCount';
  }

  @override
  Future<void> disposeEngine() async {
    initialized = false;
  }

  @override
  Future<void> disposeSynth(String synthId) async {}

  @override
  Future<String> getBackendName() async => 'fake-backend';

  @override
  Future<void> initialize({
    required double masterVolume,
    String? toneJsUrl,
  }) async {
    initialized = true;
    this.masterVolume = masterVolume;
  }

  @override
  Future<void> panic() async {}

  @override
  Future<void> setMasterVolume(double volume) async {
    masterVolume = volume;
  }

  @override
  Future<void> triggerNote({
    required String synthId,
    required double frequencyHz,
    required Duration duration,
    required double velocity,
    Duration delay = Duration.zero,
  }) async {
    triggeredNotes.add(
      TriggeredNote(
        synthId: synthId,
        frequencyHz: frequencyHz,
        duration: duration,
        velocity: velocity,
        delay: delay,
      ),
    );
  }

  @override
  Future<void> updateSynth(
    String synthId,
    SynthKitSynthOptions options,
  ) async {}
}

class TriggeredNote {
  const TriggeredNote({
    required this.synthId,
    required this.frequencyHz,
    required this.duration,
    required this.velocity,
    required this.delay,
  });

  final String synthId;
  final double frequencyHz;
  final Duration duration;
  final double velocity;
  final Duration delay;
}

class FakeClock implements SynthKitClock {
  Duration current = Duration.zero;

  @override
  Duration now() => current;
}

void main() {
  final SynthKitPlatform initialPlatform = SynthKitPlatform.instance;

  tearDown(() {
    SynthKitPlatform.instance = initialPlatform;
  });

  test('$MethodChannelSynthKit is the default instance', () {
    expect(initialPlatform, isA<MethodChannelSynthKit>());
  });

  test(
    'SynthKitNote.parse resolves note names to expected midi/frequency',
    () {
      final note = SynthKitNote.parse('A4');

      expect(note.midi, 69);
      expect(note.label, 'A4');
      expect(note.frequencyHz, closeTo(440.0, 0.001));
    },
  );

  test('transport schedules notes in beat time', () async {
    final fakePlatform = FakeSynthKitPlatform();
    final fakeClock = FakeClock();
    SynthKitPlatform.instance = fakePlatform;

    final engine = SynthKitEngine(clock: fakeClock);
    await engine.initialize(bpm: 120, masterVolume: 0.5);
    final synth = await engine.createSynth();

    await engine.transport.schedule(
      synth: synth,
      note: SynthKitNote.parse('C4'),
      beat: 2,
      durationBeats: 1,
      velocity: 0.9,
    );
    await engine.transport.start();

    expect(fakePlatform.initialized, isTrue);
    expect(fakePlatform.triggeredNotes, hasLength(1));
    expect(
      fakePlatform.triggeredNotes.single.delay,
      const Duration(seconds: 1),
    );
    expect(
      fakePlatform.triggeredNotes.single.duration,
      const Duration(milliseconds: 500),
    );
    expect(fakePlatform.triggeredNotes.single.velocity, closeTo(0.9, 0.001));

    await engine.dispose();
  });
}
