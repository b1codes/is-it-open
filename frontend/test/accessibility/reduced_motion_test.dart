import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/thermal_button.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/places/plan_visit_screen.dart';
import 'package:frontend/utils/places_theme.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';

// With the system's reduced-motion setting on ("Remove animations" on
// Android, "Reduce Motion" on iOS), Flutter reports
// MediaQuery.disableAnimations, and the app's own transitions happen at once.

/// Turns the system setting on for the rest of the test.
void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

double _sheetSize(WidgetTester tester) => tester
    .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
    .controller!
    .size;

void main() {
  testWidgets('PlacesMotion.of is zero only with reduced motion', (
    tester,
  ) async {
    late Duration normal, reduced;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          normal = PlacesMotion.of(context, PlacesMotion.standard);
          return MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                reduced = PlacesMotion.of(context, PlacesMotion.standard);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(normal, PlacesMotion.standard);
    expect(reduced, Duration.zero);
  });

  group('every implicit animation is instant', () {
    final screens = <String, (Widget, Size)>{
      'home and side menu': (const HomeScreen(), desktopSize),
      'calendar, with its sidebar': (const CalendarScreen(), desktopSize),
      'plan visit': (
        PlanVisitScreen(place: coffeePlace, saved: sampleSavedPlaces.first),
        phoneSize,
      ),
    };
    for (final MapEntry(key: name, value: (screen, size)) in screens.entries) {
      testWidgets(name, (tester) async {
        _reduceMotion(tester);
        FakeGeolocator.install(addTearDown);
        await tester.pumpApp(screen, size: size);
        await tester.pumpAndSettle();

        final animated = tester.widgetList<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        expect(animated, isNotEmpty);
        for (final container in animated) {
          expect(container.duration, Duration.zero);
        }
        await tester.unmount();
      });
    }
  });

  testWidgets('the phone sheet jumps to a tab instead of sliding', (
    tester,
  ) async {
    _reduceMotion(tester);
    FakeGeolocator.install(addTearDown);
    await tester.pumpApp(const HomeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Places').last);
    await tester.pump();
    await tester.pump();
    expect(_sheetSize(tester), closeTo(0.5, 0.01));
    await tester.unmount();
  });

  group('the button glow', () {
    Future<void> tapButton(WidgetTester tester) async {
      await tester.pumpApp(
        Center(
          child: ThermalButton(onPressed: () {}, child: const Text('JOIN')),
        ),
      );
      await tester.tap(find.text('JOIN'));
      await tester.pump();
    }

    testWidgets('plays on a tap', (tester) async {
      await tapButton(tester);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.unmount();
    });

    testWidgets('is skipped with reduced motion', (tester) async {
      _reduceMotion(tester);
      await tapButton(tester);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.unmount();
    });
  });
}
