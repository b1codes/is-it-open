import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';
import 'package:frontend/utils/places_theme.dart';

CalendarEventData<Object?> _event(
  String title, {
  Color color = Colors.teal,
  CalendarBlockKind? kind,
  int? start,
  int? end,
}) => CalendarEventData(
  title: title,
  date: DateTime(2026, 10, 19),
  startTime: start == null ? null : DateTime(2026, 10, 19, start),
  endTime: end == null ? null : DateTime(2026, 10, 19, end),
  color: color,
  event: kind,
);

BoxDecoration _decoration(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration!
        as BoxDecoration;

void main() {
  Future<void> pumpTile(WidgetTester tester, List<CalendarEventData> events) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarEventTileWidget(
              date: DateTime(2026, 10, 19),
              events: events,
              boundary: Rect.zero,
              startDuration: DateTime(2026, 10, 19, 9),
              endDuration: DateTime(2026, 10, 19, 10),
            ),
          ),
        ),
      );

  group('CalendarEventTileWidget', () {
    testWidgets('a business block is a tinted outline', (tester) async {
      await pumpTile(tester, [_event('Open', start: 9, end: 17)]);
      expect(find.text('Open'), findsOneWidget);
      expect(_decoration(tester).color, Colors.teal.withValues(alpha: 0.15));
    });

    testWidgets('a personal event is solid', (tester) async {
      final muted = PlacesTheme.light.inkMuted;
      await pumpTile(tester, [
        _event(
          'Dentist',
          color: muted,
          kind: CalendarBlockKind.personal,
          start: 9,
        ),
      ]);
      expect(_decoration(tester).color, muted.withValues(alpha: 0.9));
      final text = tester.widget<Text>(find.text('Dentist'));
      expect(text.style?.color, Colors.white);
    });

    testWidgets('the style follows the tag, not the color', (tester) async {
      final muted = PlacesTheme.light.inkMuted;
      await pumpTile(tester, [_event('Open', color: muted, start: 9)]);
      expect(_decoration(tester).color, muted.withValues(alpha: 0.15));

      await pumpTile(tester, [
        _event('Dentist', kind: CalendarBlockKind.personal, start: 9),
      ]);
      expect(_decoration(tester).color, Colors.teal.withValues(alpha: 0.9));
    });

    testWidgets('no events renders nothing', (tester) async {
      await pumpTile(tester, []);
      expect(find.byType(AnimatedContainer), findsNothing);
    });
  });

  testWidgets('FullDayEventWidget lists each event', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FullDayEventWidget(
            date: DateTime(2026, 10, 19),
            events: [
              _event('Holiday'),
              _event(
                'Trip',
                color: PlacesTheme.light.inkMuted,
                kind: CalendarBlockKind.personal,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('Trip'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Trip')).style?.color, Colors.white);
    // In ink, not the event's color, which the block is only tinted with.
    expect(
      tester.widget<Text>(find.text('Holiday')).style?.color,
      PlacesTheme.light.ink,
    );
  });

  group('StackEventArranger', () {
    List<OrganizedCalendarEventData<Object?>> arrange(
      List<CalendarEventData<Object?>> events, {
      DateTime? on,
    }) => const StackEventArranger<Object?>().arrange(
      calendarViewDate: on ?? DateTime(2026, 10, 19),
      events: events,
      height: 1440,
      width: 100,
      heightPerMinute: 1,
      startHour: 0,
    );

    test('puts opening hours first and planned visits last', () {
      final arranged = arrange([
        _event('Planned Visit', start: 10, end: 11),
        _event('Dentist', start: 9, end: 10),
        _event('Open', start: 8, end: 17),
      ]);
      expect(arranged.map((e) => e.events.single.title), [
        'Open',
        'Dentist',
        'Planned Visit',
      ]);
    });

    test('spans the full width at the event\'s time', () {
      final [block] = arrange([_event('Open', start: 9, end: 17)]);
      expect(block.top, 9 * 60);
      expect(block.bottom, 1440 - 17 * 60);
      expect((block.left, block.right), (0.0, 0.0));
    });

    test('an event past midnight runs to the bottom', () {
      final late = CalendarEventData<Object?>(
        title: 'Open',
        date: DateTime(2026, 10, 19),
        startTime: DateTime(2026, 10, 19, 22),
        endTime: DateTime(2026, 10, 20, 2),
      );
      final [block] = arrange([late]);
      expect(block.top, 22 * 60);
      expect(block.bottom, 0);
    });

    group('an event from 22:00 to 02:00 the next day', () {
      final overnight = CalendarEventData<Object?>(
        title: 'Party',
        date: DateTime(2026, 10, 19),
        endDate: DateTime(2026, 10, 20),
        startTime: DateTime(2026, 10, 19, 22),
        endTime: DateTime(2026, 10, 20, 2),
      );

      test('is shown on both days', () {
        final controller = EventController<Object?>()..add(overnight);
        expect(controller.getEventsOnDay(DateTime(2026, 10, 19)), [overnight]);
        expect(controller.getEventsOnDay(DateTime(2026, 10, 20)), [overnight]);
      });

      test('runs from its start to midnight on the first', () {
        final [block] = arrange([overnight]);
        expect((block.top, block.bottom), (22 * 60.0, 0.0));
      });

      test('runs from midnight to its end on the second', () {
        final [block] = arrange([overnight], on: DateTime(2026, 10, 20));
        expect((block.top, block.bottom), (0.0, 1440 - 2 * 60.0));
      });
    });

    test('an untimed event sits at the top', () {
      final [block] = arrange([_event('Holiday')]);
      expect(block.top, 0);
    });
  });
}
