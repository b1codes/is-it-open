import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/calendar/event_details_popup.dart';

void main() {
  Future<void> open(WidgetTester tester, CalendarEventData event) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EventDetailsPopup(event: event),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a timed event with its description', (tester) async {
    await open(
      tester,
      CalendarEventData(
        title: 'Standup',
        description: 'Daily sync',
        date: DateTime(2026, 10, 19),
        startTime: DateTime(2026, 10, 19, 9, 30),
        endTime: DateTime(2026, 10, 19, 10),
        color: Colors.teal,
      ),
    );
    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('9:30 AM - 10:00 AM'), findsOneWidget);
    expect(find.text('Daily sync'), findsOneWidget);
  });

  testWidgets('an all-day event without a description', (tester) async {
    await open(
      tester,
      CalendarEventData(title: 'Holiday', date: DateTime(2026, 10, 19)),
    );
    expect(find.text('All Day'), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);
  });

  testWidgets('the close button dismisses it', (tester) async {
    await open(
      tester,
      CalendarEventData(title: 'Holiday', date: DateTime(2026, 10, 19)),
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailsPopup), findsNothing);
  });
}
