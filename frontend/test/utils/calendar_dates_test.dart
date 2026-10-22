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
}
