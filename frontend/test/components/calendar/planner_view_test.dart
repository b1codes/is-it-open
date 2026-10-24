import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/calendar/planner_view.dart';
import 'package:frontend/utils/availability_calculator.dart';
import 'package:frontend/utils/places_theme.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/pump_app.dart';

// Monday 19 Oct 2026, 10:30.
final _now = DateTime(2026, 10, 19, 10, 30);

void main() {
  late List<String> calls;
  late List<AvailabilityWindow> tapped;

  Future<void> pump(
    WidgetTester tester, {
    DateTime? base,
    int dayCount = 3,
    List<AvailabilityWindow>? windows,
  }) async {
    calls = [];
    tapped = [];
    tester.setViewport(const Size(900, 1200));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerView(
            baseDate: base ?? DateTime(2026, 10, 19),
            dayCount: dayCount,
            windows: windows ?? sampleAvailabilityWindows(_now),
            personalEvents: samplePersonalEvents(_now),
            onNavigateLeft: () => calls.add('left'),
            onNavigateRight: () => calls.add('right'),
            onNavigateToday: () => calls.add('today'),
            onWindowTap: tapped.add,
          ),
        ),
      ),
    );
  }

  testWidgets('lays out days, windows and personal events', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester);
      expect(find.text('Oct 19 – 21'), findsOneWidget);
      expect(find.text('MON'), findsOneWidget);
      expect(find.text('WED'), findsOneWidget);
      expect(find.text('6 AM'), findsOneWidget);
      expect(find.text('11 PM'), findsOneWidget);
      expect(find.text('2 places open'), findsNWidgets(3));
      expect(find.text('4 places open'), findsNWidgets(3));
      expect(find.text('Open until 6:00 PM'), findsNWidgets(3));
      expect(find.text('Standup'), findsOneWidget);
      expect(find.text('Design review'), findsOneWidget);
    });
  });

  testWidgets('marks today and draws the now line', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester);
      final monday = tester.widget<Text>(find.text('MON'));
      expect(monday.style?.color, PlacesTheme.light.anchor);
      expect(find.byType(Divider), findsOneWidget);
    });
  });

  testWidgets('no now line outside the 6am-11pm window', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 10, 19, 5)), () async {
      await pump(tester);
      expect(find.byType(Divider), findsNothing);
    });
  });

  testWidgets('tapping a window reports it', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester);
      await tester.tap(find.text('4 places open').first);
      expect(tapped.single.placeCount, 4);
    });
  });

  testWidgets('navigation buttons, and "Today" only when off screen', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester);
      expect(find.text('Today'), findsNothing);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(calls, ['left', 'right']);

      await pump(tester, base: DateTime(2026, 10, 26));
      await tester.tap(find.text('Today'));
      expect(calls, ['today']);
    });
  });

  testWidgets('header text for one day and across months', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, dayCount: 1, windows: const []);
      expect(find.text('Monday, Oct 19'), findsOneWidget);
      await pump(tester, base: DateTime(2026, 10, 30), windows: const []);
      expect(find.text('Oct 30 – Nov 1'), findsOneWidget);
    });
  });

  testWidgets('"today" follows the device clock late in the evening', (
    tester,
  ) async {
    // 11pm in New York is already the next day in UTC; today must still be
    // the 19th.
    await withClock(Clock.fixed(DateTime(2026, 10, 19, 23, 30)), () async {
      await pump(tester, base: DateTime(2026, 10, 19), windows: const []);
      expect(find.text('Today'), findsNothing);
      final monday = tester.widget<Text>(find.text('MON'));
      expect(monday.style?.color, PlacesTheme.light.anchor);
    });
  });

  // New York's clocks go back at 2am on Sunday 1 Nov 2026 (CI runs in that
  // zone): a base date of 00:30 that day plus 24 hours is 23:30 the same day.
  testWidgets('shows consecutive days across the end of daylight time', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 3, 10)), () async {
      await pump(tester, base: DateTime(2026, 11, 1, 0, 30), windows: const []);
      expect(find.text('Nov 1 – 3'), findsOneWidget);
      for (final day in ['SUN', 'MON', 'TUE']) {
        expect(find.text(day), findsOneWidget);
      }
      // Today, Tuesday the 3rd, is the last day shown.
      expect(find.text('Today'), findsNothing);
    });
  });

  // And forward at 2am on Sunday 8 Mar: 23:30 on the 7th plus 24 hours is
  // 00:30 on the 9th.
  testWidgets('shows consecutive days across the start of daylight time', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 3, 8, 10)), () async {
      await pump(tester, base: DateTime(2026, 3, 7, 23, 30), windows: const []);
      expect(find.text('Mar 7 – 9'), findsOneWidget);
      for (final day in ['SAT', 'SUN', 'MON']) {
        expect(find.text(day), findsOneWidget);
      }
      expect(find.text('Today'), findsNothing);
    });
  });
}
