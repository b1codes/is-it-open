import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:frontend/utils/availability_calculator.dart';
import 'package:flutter/material.dart';

void main() {
  test('calculateAvailableWindows subtracts personal events from business hours', () {
    final baseDate = DateTime(2026, 4, 21);
    
    final businessBlocks = [
      CalendarEventData(
        title: 'Work',
        date: baseDate,
        startTime: DateTime(2026, 4, 21, 9, 0),
        endTime: DateTime(2026, 4, 21, 17, 0),
        color: Colors.green,
      )
    ];

    final personalEvents = [
      CalendarEventData(
        title: 'Lunch',
        date: baseDate,
        startTime: DateTime(2026, 4, 21, 12, 0),
        endTime: DateTime(2026, 4, 21, 13, 0),
      )
    ];

    final result = AvailabilityCalculator.calculateAvailableWindows(businessBlocks, personalEvents);

    expect(result.length, 2);
    expect(result[0].startTime, DateTime(2026, 4, 21, 9, 0));
    expect(result[0].endTime, DateTime(2026, 4, 21, 12, 0));
    expect(result[1].startTime, DateTime(2026, 4, 21, 13, 0));
    expect(result[1].endTime, DateTime(2026, 4, 21, 17, 0));
  });
}
