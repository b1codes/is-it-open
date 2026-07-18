import 'package:icalendar_parser/icalendar_parser.dart';

void main() {
  const ics = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test Product//EN
BEGIN:VEVENT
SUMMARY:Test Event
DTSTART:20260517T211500Z
END:VEVENT
END:VCALENDAR''';
  final iCalendar = ICalendar.fromString(ics);
  print("Parsed ICalendar: ${iCalendar.data}");
  final event = iCalendar.data.firstWhere((e) => e['type'] == 'VEVENT');
  final dtstart = event['dtstart'] as IcsDateTime;
  print("dtstart.dt: '${dtstart.dt}'");
  print("dtstart.tzid: '${dtstart.tzid}'");
}
