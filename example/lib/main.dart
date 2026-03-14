import 'package:synthkit/synthkit.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const SynthKitExampleApp());
}

class SynthKitExampleApp extends StatelessWidget {
  const SynthKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SynthKit Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF184E77)),
      ),
      home: const SynthKitExampleScreen(),
    );
  }
}

class SynthKitExampleScreen extends StatefulWidget {
  const SynthKitExampleScreen({super.key});

  @override
  State<SynthKitExampleScreen> createState() => _SynthKitExampleScreenState();
}

class _SynthKitExampleScreenState extends State<SynthKitExampleScreen> {
  final SynthKitEngine _engine = SynthKitEngine();
  SynthKitSynth? _synth;
  String _status = 'Tap Initialize to unlock audio and create the synth.';
  bool _busy = false;

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _run(() async {
      await _engine.initialize(bpm: 112, masterVolume: 0.7);
      _synth ??= await _engine.createSynth(
        const SynthKitSynthOptions(
          waveform: SynthKitWaveform.sawtooth,
          envelope: SynthKitEnvelope(
            attack: Duration(milliseconds: 8),
            decay: Duration(milliseconds: 140),
            sustain: 0.65,
            release: Duration(milliseconds: 260),
          ),
          filter: SynthKitFilter.lowPass(cutoffHz: 1600),
          volume: 0.75,
        ),
      );
      final backend = await _engine.backendName;
      _setStatus('Ready on $backend');
    });
  }

  Future<void> _playOneShot() async {
    await _ensureReady();
    await _run(() async {
      await _synth!.triggerAttackRelease(
        SynthKitNote.parse('C4'),
        const Duration(milliseconds: 380),
      );
      _setStatus('Played C4.');
    });
  }

  Future<void> _playPattern() async {
    await _ensureReady();
    await _run(() async {
      await _engine.transport.stop(clearSequence: true);
      await _engine.transport.setBpm(112);
      await _engine.transport.schedule(
        synth: _synth!,
        note: SynthKitNote.parse('A3'),
        beat: 0,
        durationBeats: 0.5,
      );
      await _engine.transport.schedule(
        synth: _synth!,
        note: SynthKitNote.parse('C4'),
        beat: 1,
        durationBeats: 0.5,
      );
      await _engine.transport.schedule(
        synth: _synth!,
        note: SynthKitNote.parse('E4'),
        beat: 2,
        durationBeats: 0.5,
      );
      await _engine.transport.schedule(
        synth: _synth!,
        note: SynthKitNote.parse('G4'),
        beat: 3,
        durationBeats: 1,
      );
      await _engine.transport.start();
      _setStatus('Scheduled a short four-beat pattern.');
    });
  }

  Future<void> _stop() async {
    await _run(() async {
      await _engine.transport.stop();
      _setStatus('Stopped transport and cleared active notes.');
    });
  }

  Future<void> _ensureReady() async {
    if (_synth != null) {
      return;
    }
    await _initialize();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } catch (error) {
      _setStatus('Error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _setStatus(String status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SynthKit Example')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _initialize,
              child: const Text('Initialize'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy ? null : _playOneShot,
              child: const Text('Play One Shot'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy ? null : _playPattern,
              child: const Text('Play Pattern'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _stop,
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}
