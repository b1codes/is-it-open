import 'package:calendar_view/calendar_view.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_event.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';
import 'package:frontend/components/calendar/calendar_sidebar.dart';
import 'package:frontend/models/hours.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:latlong2/latlong.dart';

import '../../helpers/pump_app.dart';

// Wednesday 21 Oct 2026; the week shown is Mon 19 - Sun 25 Oct.
final _now = DateTime(2026, 10, 21, 8);

SavedPlace _openOn(int dayOfWeek, String id) => SavedPlace(
  id: dayOfWeek,
  place: Place(
    tomtomId: id,
    name: id,
    address: '',
    location: const LatLng(40.7, -74),
    hours: [
      BusinessHours(
        dayOfWeek: dayOfWeek,
        openTime: const TimeOfDay(hour: 9, minute: 0),
        closeTime: const TimeOfDay(hour: 17, minute: 0),
      ),
    ],
  ),
);

CalendarDataState _data(
  List<SavedPlace> places, {
  List<CalendarEventData<Object?>> imported = const [],
  String? error,
}) => CalendarDataState(
  status: CalendarDataStatus.loaded,
  savedPlaces: places,
  checkedPlaceIds: {for (final p in places) p.place.tomtomId},
  importedEvents: imported,
  errorMessage: error,
);

Iterable<CalendarEventTileWidget> _tiles(WidgetTester tester, String title) =>
    tester
        .widgetList<CalendarEventTileWidget>(
          find.byType(CalendarEventTileWidget),
        )
        .where((t) => t.events.first.title == title);

void main() {
  Future<void> pump(
    WidgetTester tester,
    CalendarDataState data, {
    Size size = desktopSize,
    Widget screen = const CalendarScreen(),
    bool use24 = false,
  }) async {
    await tester.pumpApp(
      screen,
      calendarData: data,
      size: size,
      use24HourFormat: use24,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('draws each place\'s hours on its own weekday', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      // Monday (0) and Sunday (6) are the ends of the Mon..Sun week, where an
      // off-by-one weekday shows up first.
      await pump(tester, _data([_openOn(0, 'monday'), _openOn(6, 'sunday')]));
      final days = _tiles(
        tester,
        '1 place open',
      ).map((t) => t.date.weekday).toSet();
      expect(days, {DateTime.monday, DateTime.sunday});
    });
  });

  testWidgets('counts places open in the same window', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, _data([_openOn(2, 'a'), _openOn(2, 'b')]));
      final [tile] = _tiles(tester, '2 places open').toList();
      expect(tile.date.weekday, DateTime.wednesday);
    });
  });

  testWidgets('personal events use the personal style', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(
        tester,
        _data(
          [],
          imported: [
            CalendarEventData(
              title: 'Dentist',
              date: DateTime(2026, 10, 21),
              startTime: DateTime(2026, 10, 21, 11),
              endTime: DateTime(2026, 10, 21, 12),
            ),
          ],
        ),
      );
      final [tile] = _tiles(tester, 'Dentist').toList();
      expect(tile.events.first.color, PlacesTheme.light.inkMuted);
      expect(
        tester.widget<Text>(find.text('Dentist')).style?.color,
        Colors.white,
      );
    });
  });

  testWidgets('the Places and Personal toggles hide each layer', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(
        tester,
        _data(
          [_openOn(2, 'a')],
          imported: [
            CalendarEventData(
              title: 'Dentist',
              date: DateTime(2026, 10, 21),
              startTime: DateTime(2026, 10, 21, 7),
              endTime: DateTime(2026, 10, 21, 8),
            ),
          ],
        ),
      );
      expect(_tiles(tester, '1 place open'), isNotEmpty);
      expect(_tiles(tester, 'Dentist'), isNotEmpty);

      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();
      expect(_tiles(tester, '1 place open'), isEmpty);

      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();
      expect(_tiles(tester, 'Dentist'), isEmpty);
    });
  });

  testWidgets('desktop: the sidebar collapses and expands', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, _data([_openOn(2, 'a')]));
      expect(find.byType(CalendarSidebarWidget), findsOneWidget);
      expect(find.text('My Places'), findsOneWidget);
      await tester.tap(find.byTooltip('Collapse Sidebar'));
      await tester.pumpAndSettle();
      expect(find.text('My Places'), findsNothing);
      await tester.tap(find.byTooltip('Expand Sidebar'));
      await tester.pumpAndSettle();
      expect(find.text('My Places'), findsOneWidget);
    });
  });

  testWidgets('a tablet-width window starts with the sidebar collapsed', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, _data([]), size: const Size(800, 900));
      expect(find.byTooltip('Expand Sidebar'), findsOneWidget);
    });
  });

  testWidgets('phone: the filter button opens the sidebar drawer', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, _data([_openOn(2, 'a')]), size: phoneSize);
      expect(find.byType(CalendarSidebarWidget), findsNothing);
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.byType(CalendarSidebarWidget), findsOneWidget);
    });
  });

  testWidgets('shows calendar errors in a snackbar', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, _data([]));
      tester
          .element(find.byType(CalendarScreen))
          .read<CalendarDataBloc>()
          .add(const ImportIcalFile('not a calendar'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error importing iCal'), findsOneWidget);
    });
  });

  testWidgets('embedded, it has no app bar', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(
        tester,
        _data([]),
        screen: const Scaffold(body: CalendarScreen(embedded: true)),
      );
      expect(find.text('Plan'), findsNothing);
      expect(find.text('Oct 19 – 25, 2026'), findsOneWidget);
    });
  });

  testWidgets('uses the 24-hour setting for time labels', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await pump(tester, _data([]), use24: true);
      expect(find.text('13:00'), findsWidgets);
    });
  });
}
