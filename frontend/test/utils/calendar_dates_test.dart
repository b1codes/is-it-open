import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/calendar_dates.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('lastDayOfTimedEvent', () {
    test('is the start day for an event within one day', () {
      expect(
        lastDayOfTimedEvent(
          DateTime(2026, 10, 23, 9),
          DateTime(2026, 10, 23, 17),
        ),
        DateTime(2026, 10, 23),
      );
    });

    test('is the end day for an event past midnight', () {
      expect(
        lastDayOfTimedEvent(
          DateTime(2026, 10, 23, 22),
          DateTime(2026, 10, 24, 2),
        ),
        DateTime(2026, 10, 24),
      );
    });

    test('is the day before an end exactly at midnight', () {
      expect(
        lastDayOfTimedEvent(DateTime(2026, 10, 23, 22), DateTime(2026, 10, 24)),
        DateTime(2026, 10, 23),
      );
      expect(
        lastDayOfTimedEvent(DateTime(2026, 10, 22, 22), DateTime(2026, 10, 25)),
        DateTime(2026, 10, 24),
      );
    });

    test("reads a device calendar's zoned times on their own clock", () {
      tzdata.initializeTimeZones();
      final tokyo = tz.getLocation('Asia/Tokyo');
      expect(
        lastDayOfTimedEvent(
          tz.TZDateTime(tokyo, 2026, 10, 23, 22),
          tz.TZDateTime(tokyo, 2026, 10, 24),
        ),
        DateTime(2026, 10, 23),
      );
    });

    test('is never before the start day', () {
      expect(
        lastDayOfTimedEvent(
          DateTime(2026, 10, 23, 9),
          DateTime(2026, 10, 23, 8),
        ),
        DateTime(2026, 10, 23),
      );
      expect(
        lastDayOfTimedEvent(DateTime(2026, 10, 23), DateTime(2026, 10, 23)),
        DateTime(2026, 10, 23),
      );
    });
  });

  // New York's clocks go back at 2am on Sunday 1 Nov 2026 and forward at
  // 2am on Sunday 8 Mar 2026 (CI runs in that zone), so 24 hours from just
  // after midnight on 1 Nov is 23:30 the same day, and 24 hours from 23:30
  // on 7 Mar is 00:30 on 9 Mar.
  group('addCalendarDays', () {
    test('moves by calendar days at the same wall-clock time', () {
      expect(
        addCalendarDays(DateTime(2026, 10, 19, 10, 30), 3),
        DateTime(2026, 10, 22, 10, 30),
      );
      expect(
        addCalendarDays(DateTime(2026, 12, 30, 8), 3),
        DateTime(2027, 1, 2, 8),
      );
      expect(
        addCalendarDays(DateTime(2026, 3, 1, 9), -1),
        DateTime(2026, 2, 28, 9),
      );
    });

    test('lands on the next day across the end of daylight time', () {
      expect(
        addCalendarDays(DateTime(2026, 11, 1, 0, 30), 1),
        DateTime(2026, 11, 2, 0, 30),
      );
      expect(
        addCalendarDays(DateTime(2026, 11, 1, 23, 30), -6),
        DateTime(2026, 10, 26, 23, 30),
      );
    });

    test("doesn't skip a day across the start of daylight time", () {
      expect(
        addCalendarDays(DateTime(2026, 3, 7, 23, 30), 1),
        DateTime(2026, 3, 8, 23, 30),
      );
      expect(
        addCalendarDays(DateTime(2026, 3, 8, 23, 30), -1),
        DateTime(2026, 3, 7, 23, 30),
      );
    });
  });
}
