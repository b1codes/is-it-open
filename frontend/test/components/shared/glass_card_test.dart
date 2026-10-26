import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/glass_card.dart';
import 'package:frontend/utils/app_theme.dart';

BoxDecoration _decoration(WidgetTester tester) =>
    tester.widget<Container>(find.byType(Container)).decoration!
        as BoxDecoration;

void main() {
  testWidgets('takes blur and opacity from the theme effects', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const GlassCard(child: Text('card')),
      ),
    );
    final effects = AppTheme.lightTheme.extension<AppEffects>()!;
    expect(find.text('card'), findsOneWidget);
    expect(
      _decoration(tester).color,
      AppColors.glassSurface.withValues(alpha: effects.glassOpacity),
    );
    expect(_decoration(tester).borderRadius, BorderRadius.circular(12));
  });

  testWidgets('falls back to defaults without theme effects', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GlassCard(child: SizedBox())),
    );
    expect(
      _decoration(tester).color,
      AppColors.glassSurface.withValues(alpha: 0.05),
    );
  });

  testWidgets('honors explicit styling', (tester) async {
    final border = Border.all(color: Colors.orange);
    await tester.pumpWidget(
      MaterialApp(
        home: GlassCard(
          blur: 1,
          opacity: 0.4,
          color: Colors.blue,
          borderRadius: BorderRadius.circular(3),
          padding: EdgeInsets.zero,
          border: border,
          child: const SizedBox(),
        ),
      ),
    );
    expect(_decoration(tester).color, Colors.blue.withValues(alpha: 0.4));
    expect(_decoration(tester).border, border);
    expect(
      tester.widget<Container>(find.byType(Container)).padding,
      EdgeInsets.zero,
    );
  });
}
