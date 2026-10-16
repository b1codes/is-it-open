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

  test('UTC and TZID start times for the same instant agree', () {
    const icsUtc = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test Product//EN
BEGIN:VEVENT
SUMMARY:Test Event Z
DTSTART:20260517T211500Z
DTEND:20260517T221500Z
END:VEVENT
END:VCALENDAR''';
    const icsTzid = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test Product//EN
BEGIN:VEVENT
SUMMARY:Test Event TZID
DTSTART;TZID=America/New_York:20260517T171500
DTEND;TZID=America/New_York:20260517T181500
END:VEVENT
END:VCALENDAR''';

    final utcStart = service.parse(icsUtc).single.startTime!.toUtc();
    final tzidStart = service.parse(icsTzid).single.startTime!.toUtc();
    expect(utcStart, DateTime.utc(2026, 5, 17, 21, 15));
    expect(tzidStart, utcStart);
  });

  test('weekly RRULE with WKST expands only on its BYDAY days', () {
    const ics = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test Product//EN
BEGIN:VEVENT
SUMMARY:Test Event WKST
DTSTART:20260519T150000Z
DTEND:20260519T160000Z
RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=TU,TH;COUNT=4
END:VEVENT
END:VCALENDAR''';

    final events = service.parse(ics);
    expect(events, hasLength(4));
    expect(
      events.map((e) => e.startTime!.toUtc().weekday),
      everyElement(anyOf(DateTime.tuesday, DateTime.thursday)),
    );
  });
}
