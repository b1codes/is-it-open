import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/glass_container.dart';

BoxDecoration _decoration(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .single;

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {Brightness? b}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: b ?? Brightness.light),
        home: Center(child: child),
      ),
    );
    await tester.pumpAndSettle(); // theme changes animate
  }

  testWidgets('tints its color, sizes itself and shows the child', (
    tester,
  ) async {
    await pump(
      tester,
      const GlassContainer(
        width: 120,
        height: 60,
        color: Colors.red,
        opacity: 0.5,
        padding: EdgeInsets.all(4),
        child: Text('inside'),
      ),
    );
    expect(find.text('inside'), findsOneWidget);
    expect(_decoration(tester).color, Colors.red.withValues(alpha: 0.5));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.getSize(find.byType(GlassContainer)), const Size(120, 60));
  });

  testWidgets('default border contrasts with the theme brightness', (
    tester,
  ) async {
    await pump(tester, const GlassContainer(child: SizedBox()));
    final light = (_decoration(tester).border! as Border).top.color;
    await pump(
      tester,
      const GlassContainer(child: SizedBox()),
      b: Brightness.dark,
    );
    final dark = (_decoration(tester).border! as Border).top.color;
    expect(light, Colors.black.withValues(alpha: 0.1));
    expect(dark, Colors.white.withValues(alpha: 0.1));
  });

  testWidgets('uses a custom border and radius', (tester) async {
    final border = Border.all(color: Colors.green);
    await pump(
      tester,
      GlassContainer(
        border: border,
        borderRadius: BorderRadius.circular(9),
        child: const SizedBox(),
      ),
    );
    expect(_decoration(tester).border, border);
    expect(_decoration(tester).borderRadius, BorderRadius.circular(9));
  });
}
