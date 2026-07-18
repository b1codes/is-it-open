import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:frontend/services/ical_parser_service.dart';

void main() {
  test('test wkst removal', () async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));

    final service = IcalParserService();

    const icsWkst = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test Product//EN
BEGIN:VEVENT
SUMMARY:Test Event WKST
DTSTART:20260517T211500Z
RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=TU,TH
END:VEVENT
END:VCALENDAR''';

    final events = service.parse(icsWkst);
    print("Parsed \${events.length} events successfully");
  });
}
