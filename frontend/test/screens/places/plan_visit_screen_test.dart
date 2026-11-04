import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/hours.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/places/plan_visit_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

// Monday 19 Oct 2026.
DateTime _mon(int hour, [int minute = 0]) =>
    DateTime(2026, 10, 19, hour, minute);

SavedPlace _saved(Place place, {int? visit}) =>
    SavedPlace(id: 1, place: place, averageVisitLength: visit);

Place _place(List<BusinessHours> hours) => Place(
  tomtomId: 'tt_plan',
  name: 'Plan Place',
  address: '',
  location: const LatLng(0, 0),
  hours: hours,
);

BusinessHours _monday(int open, int close) => BusinessHours(
  dayOfWeek: 0,
  openTime: TimeOfDay(hour: open, minute: 0),
  closeTime: TimeOfDay(hour: close, minute: 0),
);

void main() {
  late MockApiService api;

  setUp(() {
    api = MockApiService();
    when(() => api.updateVisitLength(any(), any())).thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester,
    Place place, {
    int? visit,
    bool use24 = false,
  }) async {
    await tester.pumpApp(
      PlanVisitScreen(
        place: place,
        saved: _saved(place, visit: visit),
      ),
      api: api,
      use24HourFormat: use24,
      size: const Size(600, 1200),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('picking a length saves it and explains how it is used', (
    tester,
  ) async {
    await withClock(Clock.fixed(_mon(8)), () async {
      await pump(tester, _place([_monday(9, 17)]));
      expect(find.textContaining('No typical length set'), findsOneWidget);
      await tester.tap(find.text('45 min'));
      await tester.pumpAndSettle();
      verify(() => api.updateVisitLength('tt_plan', 45)).called(1);
      expect(find.textContaining('use 45 min'), findsOneWidget);

      // Clearing it saves null; re-picking the current one does nothing.
      await tester.tap(find.text('No length'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No length'));
      await tester.pumpAndSettle();
      verify(() => api.updateVisitLength('tt_plan', null)).called(1);
    });
  });

  testWidgets('formats hours and half hours', (tester) async {
    await withClock(Clock.fixed(_mon(8)), () async {
      await pump(tester, _place([]), visit: 90);
      expect(find.text('1.5 hr'), findsOneWidget);
      expect(find.text('2 hr'), findsOneWidget);
      expect(find.textContaining('use 1.5 hr'), findsOneWidget);
    });
  });

  testWidgets('a failed save reverts the choice', (tester) async {
    when(
      () => api.updateVisitLength(any(), any()),
    ).thenThrow(ApiException('down'));
    await withClock(Clock.fixed(_mon(8)), () async {
      await pump(tester, _place([_monday(9, 17)]), visit: 30);
      await tester.tap(find.text('1 hr'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't update visit length."), findsOneWidget);
      expect(find.textContaining('use 30 min'), findsOneWidget);
    });
  });

  testWidgets('back returns the chosen length', (tester) async {
    late Future<int?> result;
    await withClock(Clock.fixed(_mon(8)), () async {
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => result = Navigator.of(context).push<int?>(
              MaterialPageRoute(
                builder: (_) => PlanVisitScreen(
                  place: coffeePlace,
                  saved: sampleSavedPlaces.first,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        api: api,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 hr'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(await result, 60);
    });
  });

  group("today's windows", () {
    testWidgets('a window yet to open shows its length', (tester) async {
      await withClock(Clock.fixed(_mon(8)), () async {
        await pump(tester, _place([_monday(9, 17)]), visit: 60);
        expect(find.text('9am – 5pm'), findsOneWidget);
        expect(find.text('8h window.'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      });
    });

    testWidgets('an open window shows the time left', (tester) async {
      await withClock(Clock.fixed(_mon(15, 30)), () async {
        await pump(tester, _place([_monday(9, 17)]), visit: 60);
        expect(find.text('1h 30m left in this window.'), findsOneWidget);
      });
    });

    testWidgets('warns when too little of an open window is left', (
      tester,
    ) async {
      await withClock(Clock.fixed(_mon(16, 30)), () async {
        await pump(tester, _place([_monday(9, 17)]), visit: 60);
        expect(find.text('Less than 1h left.'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      });
    });

    testWidgets('warns when a window is shorter than the visit', (
      tester,
    ) async {
      await withClock(Clock.fixed(_mon(8)), () async {
        await pump(tester, _place([_monday(12, 13)]), visit: 90);
        expect(find.text('Shorter than 1h 30m.'), findsOneWidget);
      });
    });

    testWidgets('a closed window says so', (tester) async {
      await withClock(Clock.fixed(_mon(18)), () async {
        await pump(tester, _place([_monday(9, 17)]), use24: true);
        expect(find.text('09:00 – 17:00'), findsOneWidget);
        expect(find.text('Already closed.'), findsOneWidget);
      });
    });

    testWidgets('a window past midnight counts its full length', (
      tester,
    ) async {
      await withClock(Clock.fixed(_mon(12)), () async {
        await pump(tester, _place([_monday(18, 2)]));
        expect(find.text('8h window.'), findsOneWidget);
      });
    });

    testWidgets('closed today, or no hours at all', (tester) async {
      await withClock(Clock.fixed(_mon(12)), () async {
        await pump(
          tester,
          _place([
            const BusinessHours(
              dayOfWeek: 3,
              openTime: TimeOfDay(hour: 9, minute: 0),
              closeTime: TimeOfDay(hour: 17, minute: 0),
            ),
          ]),
        );
        expect(find.text('Closed today.'), findsOneWidget);
        await pump(tester, _place([]));
        expect(find.text('No hours on file for this place.'), findsOneWidget);
      });
    });
  });
}
