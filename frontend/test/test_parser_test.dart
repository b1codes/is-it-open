import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:frontend/services/ical_parser_service.dart';

void main() {
  test('test parser output', () async {
    tz.initializeTimeZones();
    try {
      // In tests, flutter_timezone might fail, so we fallback
      tz.setLocalLocation(tz.getLocation('America/New_York'));
    } catch (e) {
      print("Error getting timezone: \$e");
    }

    final service = IcalParserService();

    const icsZ = '''BEGIN:VCALENDAR
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

    final eventsZ = service.parse(icsZ);
    print("Z Event Start: ${eventsZ.first.startTime}");

    final eventsTzid = service.parse(icsTzid);
    print("TZID Event Start: ${eventsTzid.first.startTime}");
  });
}
