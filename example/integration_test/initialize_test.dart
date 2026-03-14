import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:synthkit_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initialize and playback controls do not crash', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Basic Synth').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play One-Shot  C4'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Played C4 one-shot.'), findsOneWidget);

    await tester.tap(find.text('Play Pattern'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Playing A3–C4–E4–G4 at 112 BPM.'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Transport stopped.'), findsOneWidget);
  });

  testWidgets('lofi example schedules and starts without surfacing an error', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lo-Fi Beat').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('PLAY  LO-FI'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Playing 8-bar lo-fi at 78 BPM...'), findsOneWidget);
    expect(find.textContaining('Error:'), findsNothing);

    await tester.tap(find.text('STOP'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Stopped lo-fi sequence.'), findsOneWidget);
  });
}
