abstract class SynthKitClock {
  Duration now();
}

class SystemSynthKitClock implements SynthKitClock {
  SystemSynthKitClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  Duration now() => _stopwatch.elapsed;
}
