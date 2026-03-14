import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:synthkit_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initialize and playback controls do not crash', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Initialize'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Ready on'), findsOneWidget);

    await tester.tap(find.text('Play One Shot'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Played C4.'), findsOneWidget);

    await tester.tap(find.text('Play Pattern'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Scheduled a short four-beat pattern.'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Stopped transport and cleared active notes.'), findsOneWidget);
  });
}
