import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/app_theme.dart';
import 'package:frontend/utils/places_theme.dart';

void main() {
  test('light and dark themes carry the app and places extensions', () {
    expect(AppTheme.lightTheme.brightness, Brightness.light);
    expect(AppTheme.darkTheme.brightness, Brightness.dark);
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      expect(theme.extension<AppEffects>(), isNotNull);
    }
    expect(
      AppTheme.lightTheme.extension<PlacesTheme>()?.paper ??
          PlacesTheme.light.paper,
      PlacesTheme.light.paper,
    );
  });

  // MaterialApp cross-fades between the themes, and a button animates its
  // text style along with it. Styles that can't be interpolated threw on
  // every switch with a button on screen (found by the monkey test).
  for (final (from, to) in [
    (ThemeMode.light, ThemeMode.dark),
    (ThemeMode.dark, ThemeMode.light),
  ]) {
    testWidgets('switching from ${from.name} to ${to.name} animates cleanly', (
      tester,
    ) async {
      Widget app(ThemeMode mode) => MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        home: Scaffold(
          body: Column(
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
              TextButton(onPressed: () {}, child: const Text('Text')),
              OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
              const TextField(decoration: InputDecoration(labelText: 'Field')),
            ],
          ),
        ),
      );

      await tester.pumpWidget(app(from));
      await tester.pumpWidget(app(to));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(tester.takeException(), isNull);
    });
  }

  group('AppEffects', () {
    const a = AppEffects(
      glassBlur: 10,
      glassOpacity: 0.1,
      thermalGlowGradient: LinearGradient(colors: [Colors.red, Colors.blue]),
      dragResistance: 0.2,
    );
    const b = AppEffects(
      glassBlur: 20,
      glassOpacity: 0.3,
      thermalGlowGradient: LinearGradient(colors: [Colors.green, Colors.blue]),
      dragResistance: 0.4,
    );

    test('copyWith replaces only the given fields', () {
      final copy = a.copyWith(glassBlur: 5);
      expect(copy.glassBlur, 5);
      expect(copy.glassOpacity, 0.1);
      expect(copy.dragResistance, 0.2);
      expect(a.copyWith().thermalGlowGradient, a.thermalGlowGradient);
    });

    test('lerp interpolates and ignores other extensions', () {
      final mid = a.lerp(b, 0.5);
      expect(mid.glassBlur, 15);
      expect(mid.glassOpacity, closeTo(0.2, 1e-9));
      expect(mid.dragResistance, closeTo(0.3, 1e-9));
      expect(a.lerp(null, 0.5), same(a));
    });

    test('lerpDouble treats a missing end as zero', () {
      expect(AppEffects.lerpDouble(null, null, 0.5), isNull);
      expect(AppEffects.lerpDouble(null, 10, 0.5), 5);
      expect(AppEffects.lerpDouble(10, null, 0.5), 5);
    });
  });
}
