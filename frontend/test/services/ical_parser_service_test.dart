import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/ical_parser_service.dart';

// Expected instants are compared in UTC so the tests pass in any machine
// timezone. All-day and floating events have no zone, so those compare
// wall-clock fields instead.

String _calendar(String body) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n'
    '${body.trim().split('\n').map((l) => l.trim()).join('\r\n')}\r\n'
    'END:VCALENDAR';

String _event(String props) => _calendar('BEGIN:VEVENT\n$props\nEND:VEVENT');

void main() {
  final service = IcalParserService();
  // Recurrences expand from 30 days before "now" to 180 days after.
  final now = DateTime(2026, 10, 19, 12);

  List<dynamic> parse(String ics, {Color color = Colors.blue}) =>
      withClock(Clock.fixed(now), () => service.parse(ics, eventColor: color));

  group('single events', () {
    test('parses a UTC event', () {
      final events = parse(
        _event('''
          SUMMARY:Test Event
          DESCRIPTION:Bring notes
          DTSTART:20231010T100000Z
          DTEND:20231010T110000Z
        '''),
        color: Colors.teal,
      );
      final event = events.single;
      expect(event.title, 'Test Event');
      expect(event.description, 'Bring notes');
      expect(event.color, Colors.teal);
      expect(event.startTime.toUtc(), DateTime.utc(2023, 10, 10, 10));
      expect(event.endTime.toUtc(), DateTime.utc(2023, 10, 10, 11));
    });

    test('converts a TZID time to the same instant as UTC', () {
      final utc = parse(
        _event('''
          DTSTART:20260517T211500Z
          DTEND:20260517T221500Z
        '''),
      ).single;
      final tzid = parse(
        _event('''
          DTSTART;TZID=America/New_York:20260517T171500
          DTEND;TZID=America/New_York:20260517T181500
        '''),
      ).single;
      expect(utc.startTime.toUtc(), DateTime.utc(2026, 5, 17, 21, 15));
      expect(tzid.startTime.toUtc(), utc.startTime.toUtc());
      expect(tzid.endTime.toUtc(), utc.endTime.toUtc());
    });

    test('maps Windows zone names and quoted TZIDs to IANA zones', () {
      final windows = parse(
        _event('DTSTART;TZID=Eastern Standard Time:20260115T090000'),
      ).single;
      final quoted = parse(
        _event('DTSTART;TZID="Asia/Tokyo":20260115T090000'),
      ).single;
      expect(windows.startTime.toUtc(), DateTime.utc(2026, 1, 15, 14));
      expect(quoted.startTime.toUtc(), DateTime.utc(2026, 1, 15, 0));
    });

    test('reads an unknown TZID as local wall-clock time', () {
      final event = parse(_event('DTSTART;TZID=Mars/Olympus:20260115T090000'));
      expect(event.single.startTime, DateTime(2026, 1, 15, 9));
    });

    test('keeps a floating time on the local wall clock', () {
      final event = parse(_event('DTSTART:20260115T090000')).single;
      expect(event.startTime, DateTime(2026, 1, 15, 9));
    });

    test('defaults a missing DTEND to one hour and a missing title', () {
      final event = parse(_event('DTSTART:20260115T090000Z')).single;
      expect(event.title, 'Event');
      expect(
        event.endTime.difference(event.startTime),
        const Duration(hours: 1),
      );
    });

    test('skips events without a usable DTSTART', () {
      final events = parse(
        _calendar('''
          BEGIN:VEVENT
          SUMMARY:No start
          END:VEVENT
          BEGIN:VEVENT
          SUMMARY:Bad start
          DTSTART:2026
          END:VEVENT
          BEGIN:VTODO
          SUMMARY:Not an event
          DTSTART:20260115T090000Z
          END:VTODO
        '''),
      );
      expect(events, isEmpty);
    });

    test('parses every event in a calendar', () {
      final events = parse(
        _calendar('''
          BEGIN:VEVENT
          SUMMARY:One
          DTSTART:20260115T090000Z
          END:VEVENT
          BEGIN:VEVENT
          SUMMARY:Two
          DTSTART:20260116T090000Z
          END:VEVENT
        '''),
      );
      expect(events.map((e) => e.title), ['One', 'Two']);
    });
  });

  group('all-day events', () {
    test('a one-day event has no times and ends on its start date', () {
      final event = parse(
        _event('''
          SUMMARY:Holiday
          DTSTART;VALUE=DATE:20261023
          DTEND;VALUE=DATE:20261024
        '''),
      ).single;
      expect(event.isFullDayEvent, isTrue);
      expect(event.date, DateTime(2026, 10, 23));
      expect(event.endDate, DateTime(2026, 10, 23));
      expect(event.startTime, isNull);
      expect(event.endTime, isNull);
    });

    test('a missing DTEND means one day', () {
      final event = parse(_event('DTSTART;VALUE=DATE:20261023')).single;
      expect(event.date, DateTime(2026, 10, 23));
      expect(event.endDate, DateTime(2026, 10, 23));
    });

    test('a multi-day event spans through the day before DTEND', () {
      final event = parse(
        _event('''
          SUMMARY:Trip
          DTSTART;VALUE=DATE:20261023
          DTEND;VALUE=DATE:20261026
        '''),
      ).single;
      expect(event.date, DateTime(2026, 10, 23));
      expect(event.endDate, DateTime(2026, 10, 25));
    });

    test('a multi-day event spans the US DST change', () {
      final event = parse(
        _event('''
          DTSTART;VALUE=DATE:20261031
          DTEND;VALUE=DATE:20261103
        '''),
      ).single;
      expect(event.endDate, DateTime(2026, 11, 2));
    });
  });

  group('recurrence', () {
    test('expands a weekly rule', () {
      final events = parse(
        _event('''
          DTSTART:20261012T100000Z
          DTEND:20261012T110000Z
          RRULE:FREQ=WEEKLY;COUNT=3
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2026, 10, 12, 10),
        DateTime.utc(2026, 10, 19, 10),
        DateTime.utc(2026, 10, 26, 10),
      ]);
      expect(
        events.map((e) => e.endTime.difference(e.startTime)),
        everyElement(const Duration(hours: 1)),
      );
    });

    test('expands BYDAY and ignores WKST', () {
      final events = parse(
        _event('''
          DTSTART:20261020T150000Z
          RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=TU,TH;COUNT=4
        '''),
      );
      expect(events, hasLength(4));
      expect(
        events.map((e) => e.startTime.toUtc().weekday),
        everyElement(anyOf(DateTime.tuesday, DateTime.thursday)),
      );
    });

    test('a TZID weekly event keeps its local time across DST', () {
      // New York leaves daylight time on 1 Nov 2026: 9am is 13:00Z before
      // and 14:00Z after.
      final events = parse(
        _event('''
          DTSTART;TZID=America/New_York:20261026T090000
          DTEND;TZID=America/New_York:20261026T100000
          RRULE:FREQ=WEEKLY;COUNT=3
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2026, 10, 26, 13),
        DateTime.utc(2026, 11, 2, 14),
        DateTime.utc(2026, 11, 9, 14),
      ]);
      expect(
        events.map((e) => e.endTime.difference(e.startTime)),
        everyElement(const Duration(hours: 1)),
      );
    });

    test('a TZID event keeps its local time across a spring-forward', () {
      // Europe/London moves to summer time on 29 Mar 2026.
      final events = parse(
        _event('''
          DTSTART;TZID=Europe/London:20260323T090000
          RRULE:FREQ=WEEKLY;COUNT=2
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2026, 3, 23, 9),
        DateTime.utc(2026, 3, 30, 8),
      ]);
    });

    test('a floating weekly event keeps its wall-clock time', () {
      final events = parse(
        _event('''
          DTSTART:20261026T090000
          RRULE:FREQ=WEEKLY;COUNT=3
        '''),
      );
      expect(events.map((e) => e.startTime), [
        DateTime(2026, 10, 26, 9),
        DateTime(2026, 11, 2, 9),
        DateTime(2026, 11, 9, 9),
      ]);
    });

    test('a UTC weekly event keeps its instant across DST', () {
      final events = parse(
        _event('''
          DTSTART:20261026T130000Z
          RRULE:FREQ=WEEKLY;COUNT=2
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2026, 10, 26, 13),
        DateTime.utc(2026, 11, 2, 13),
      ]);
    });

    test('expands an all-day daily rule into all-day events', () {
      final events = parse(
        _event('''
          DTSTART;VALUE=DATE:20261030
          DTEND;VALUE=DATE:20261031
          RRULE:FREQ=DAILY;COUNT=4
        '''),
      );
      expect(events.map((e) => e.date), [
        DateTime(2026, 10, 30),
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 2),
      ]);
      expect(events.map((e) => e.isFullDayEvent), everyElement(isTrue));
      expect(events.map((e) => e.endDate), events.map((e) => e.date));
    });

    test('stops 180 days ahead for an open-ended rule', () {
      final events = parse(
        _event('''
          DTSTART:20261019T100000Z
          RRULE:FREQ=DAILY
        '''),
      );
      expect(events.first.startTime.toUtc(), DateTime.utc(2026, 10, 19, 10));
      expect(
        events.last.startTime.isBefore(now.add(const Duration(days: 180))),
        isTrue,
      );
      expect(events.length, inInclusiveRange(179, 181));
    });

    test('keeps past instances back to an old DTSTART', () {
      final events = parse(
        _event('''
          DTSTART:20250101T100000Z
          RRULE:FREQ=YEARLY;COUNT=3
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc().year), [2025, 2026, 2027]);
    });

    test('falls back to the first occurrence for an invalid rule', () {
      final events = parse(
        _event('''
          DTSTART:20261019T100000Z
          RRULE:FREQ=SOMETIMES
        '''),
      );
      expect(events.single.startTime.toUtc(), DateTime.utc(2026, 10, 19, 10));
    });
  });

  group('EXDATE', () {
    test('removes an excluded UTC instance', () {
      final events = parse(
        _event('''
          DTSTART:20261012T100000Z
          RRULE:FREQ=WEEKLY;COUNT=4
          EXDATE:20261019T100000Z
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2026, 10, 12, 10),
        DateTime.utc(2026, 10, 26, 10),
        DateTime.utc(2026, 11, 2, 10),
      ]);
    });

    test('removes comma-separated and repeated EXDATEs in a TZID', () {
      final events = parse(
        _event('''
          DTSTART;TZID=America/New_York:20261026T090000
          RRULE:FREQ=WEEKLY;COUNT=5
          EXDATE;TZID=America/New_York:20261102T090000,20261109T090000
          EXDATE;TZID=America/New_York:20261123T090000
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2026, 10, 26, 13),
        DateTime.utc(2026, 11, 16, 14),
      ]);
    });

    test('matches an EXDATE given in UTC against a TZID series', () {
      final events = parse(
        _event('''
          DTSTART;TZID=America/New_York:20261026T090000
          RRULE:FREQ=WEEKLY;COUNT=2
          EXDATE:20261102T140000Z
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2026, 10, 26, 13),
      ]);
    });

    test('removes an excluded all-day date', () {
      final events = parse(
        _event('''
          DTSTART;VALUE=DATE:20261030
          RRULE:FREQ=DAILY;COUNT=3
          EXDATE;VALUE=DATE:20261031
        '''),
      );
      expect(events.map((e) => e.date), [
        DateTime(2026, 10, 30),
        DateTime(2026, 11, 1),
      ]);
    });

    test('ignores an EXDATE that matches no instance', () {
      final events = parse(
        _event('''
          DTSTART:20261012T100000Z
          RRULE:FREQ=WEEKLY;COUNT=2
          EXDATE:20261013T100000Z
        '''),
      );
      expect(events, hasLength(2));
    });
  });
}
