import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/address_input_accordion.dart';

void main() {
  late List<TextEditingController> controllers;

  setUp(() => controllers = List.generate(4, (_) => TextEditingController()));
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
  });

  Future<void> pump(WidgetTester tester, {bool expanded = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressInputAccordion(
              title: 'Home',
              icon: Icons.home,
              streetController: controllers[0],
              cityController: controllers[1],
              stateController: controllers[2],
              zipController: controllers[3],
              initiallyExpanded: expanded,
            ),
          ),
        ),
      );

  testWidgets('starts collapsed and expands on tap', (tester) async {
    await pump(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Street Address'), findsNothing);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Street Address'), findsOneWidget);
  });

  testWidgets('writes each field to its controller', (tester) async {
    await pump(tester, expanded: true);
    final labels = ['Street Address', 'City', 'State', 'Zip Code'];
    final values = ['1 Main St', 'Springfield', 'IL', '62701'];
    for (var i = 0; i < 4; i++) {
      await tester.enterText(
        find.widgetWithText(TextFormField, labels[i]),
        values[i],
      );
    }
    expect(controllers.map((c) => c.text), values);
  });
}
