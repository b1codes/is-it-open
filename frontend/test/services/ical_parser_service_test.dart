import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/ical_parser_service.dart';

void main() {
  final service = IcalParserService();

  test('should parse a single timed event', () {
    const ics = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test Product//EN
BEGIN:VEVENT
SUMMARY:Test Event
DTSTART:20231010T100000Z
DTEND:20231010T110000Z
END:VEVENT
END:VCALENDAR''';
    final events = service.parse(ics);
    expect(events.length, 1);
    expect(events.first.title, 'Test Event');

    // 10:00 Z is converted to native local time.
    // We check the UTC hour to ensure the absolute moment in time is correct regardless of the test runner's OS timezone.
    expect(events.first.startTime?.toUtc().hour, 10);
  });

  test('should expand weekly recurring event', () {
    const ics = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test Product//EN
BEGIN:VEVENT
SUMMARY:Weekly Meeting
DTSTART:20260512T100000Z
DTEND:20260512T110000Z
RRULE:FREQ=WEEKLY;COUNT=3
END:VEVENT
END:VCALENDAR''';
    final events = service.parse(ics);
    expect(events.length, 3);

    expect(events[0].startTime?.toUtc().day, 12);
    expect(events[1].startTime?.toUtc().day, 19);
    expect(events[2].startTime?.toUtc().day, 26);

    expect(events[0].startTime?.toUtc().hour, 10);
  });

  test('should handle events with TZID', () {
    const ics = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test Product//EN
BEGIN:VEVENT
SUMMARY:Tokyo Meeting
DTSTART;TZID=Asia/Tokyo:20231010T100000
DTEND;TZID=Asia/Tokyo:20231010T110000
END:VEVENT
END:VCALENDAR''';

    final events = service.parse(ics);
    expect(events.length, 1);
    expect(events.first.title, 'Tokyo Meeting');
  });
}
