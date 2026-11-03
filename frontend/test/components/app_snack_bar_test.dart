import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/app_snack_bar.dart';

void main() {
  Future<String> heroTag(WidgetTester tester, SnackBar snackBar) async {
    final messenger = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger),
    );
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(snackBar);
    await tester.pump();
    return tester.widget<Hero>(find.byType(Hero)).tag as String;
  }

  testWidgets('two with the same content have different hero tags', (
    tester,
  ) async {
    // Flutter tags a SnackBar's hero by its content, so a plain SnackBar
    // replaced by another saying the same thing shared its tag (#61).
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    final plain = [
      await heroTag(tester, const SnackBar(content: Text('Offline'))),
      await heroTag(tester, const SnackBar(content: Text('Offline'))),
    ];
    final app = [
      await heroTag(tester, AppSnackBar(content: const Text('Offline'))),
      await heroTag(tester, AppSnackBar(content: const Text('Offline'))),
    ];

    expect(plain[0], plain[1]);
    expect(app[0], isNot(app[1]));
  });

  testWidgets('keeps its own options', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final snackBar = AppSnackBar(
      content: const Text('Saved'),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 1),
    );
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .showSnackBar(snackBar);
    await tester.pump();

    expect(find.text('Saved'), findsOneWidget);
    expect(snackBar.backgroundColor, Colors.green);
    expect(snackBar.duration, const Duration(seconds: 1));
  });

  test('the app builds no plain SnackBar', () {
    // Page heroes are on, so a plain SnackBar can hit #61 again.
    final plain = RegExp(r'(?<![A-Za-z_])SnackBar\(');
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith('app_snack_bar.dart'))
          for (final (i, line) in file.readAsLinesSync().indexed)
            if (plain.hasMatch(line)) '${file.path}:${i + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty, reason: 'Use AppSnackBar instead.');
  });
}
