import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/thermal_button.dart';
import 'package:frontend/utils/app_theme.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onPressed,
    bool isLoading = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Center(
        child: ThermalButton(
          onPressed: onPressed,
          isLoading: isLoading,
          child: const Text('Go'),
        ),
      ),
    ),
  );

  testWidgets('calls onPressed and plays the glow', (tester) async {
    var taps = 0;
    await pump(tester, onPressed: () => taps++);
    await tester.tap(find.text('Go'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, 1);
    expect(
      find.descendant(
        of: find.byType(ThermalButton),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('is disabled without onPressed', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Go'));
    await tester.pump();
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(ThermalButton),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.enabled, isFalse);
    expect(
      find.descendant(
        of: find.byType(ThermalButton),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('shows a spinner and ignores taps while loading', (tester) async {
    var taps = 0;
    await pump(tester, onPressed: () => taps++, isLoading: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(ThermalButton));
    await tester.pump();
    expect(taps, 0);
  });
}
