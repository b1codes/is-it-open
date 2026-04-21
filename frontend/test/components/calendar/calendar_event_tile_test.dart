import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';
import 'package:frontend/components/shared/glass_card.dart';

void main() {
  testWidgets('CalendarEventTileWidget uses GlassCard', (
    WidgetTester tester,
  ) async {
    final event = CalendarEventData(
      title: 'Test Event',
      date: DateTime.now(),
      color: Colors.blue,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarEventTileWidget(
            date: DateTime.now(),
            events: [event],
            boundary: Rect.zero,
            startDuration: DateTime.now(),
            endDuration: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      ),
    );

    expect(find.byType(GlassCard), findsOneWidget);
    expect(find.text('Test Event'), findsOneWidget);
  });
}
