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

    test('a DTEND in another zone gives the real length', () {
      // A 7-hour flight: 18:00 in New York is 23:00Z, 06:00 in London 06:00Z.
      final flight = parse(
        _event('''
          DTSTART;TZID=America/New_York:20260301T180000
          DTEND;TZID=Europe/London:20260302T060000
        '''),
      ).single;
      expect(flight.startTime.toUtc(), DateTime.utc(2026, 3, 1, 23));
      expect(flight.endTime.toUtc(), DateTime.utc(2026, 3, 2, 6));
    });

    test('a UTC DTSTART with a zoned DTEND keeps its length', () {
      // 11:00 in New York is 16:00Z: one hour, though its wall clock is
      // earlier than the start's.
      final event = parse(
        _event('''
          DTSTART:20260301T150000Z
          DTEND;TZID=America/New_York:20260301T110000
        '''),
      ).single;
      expect(event.endTime.toUtc(), DateTime.utc(2026, 3, 1, 16));
    });

    test('a recurring flight keeps its length on every instance', () {
      final flights = parse(
        _event('''
          DTSTART;TZID=America/New_York:20261101T180000
          DTEND;TZID=Europe/London:20261102T060000
          RRULE:FREQ=WEEKLY;COUNT=2
        '''),
      );
      expect(
        flights.map((e) => e.endTime.difference(e.startTime)),
        everyElement(const Duration(hours: 7)),
      );
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
      // Europe/London moves to summer time on 28 Mar 2027.
      final events = parse(
        _event('''
          DTSTART;TZID=Europe/London:20270322T090000
          RRULE:FREQ=WEEKLY;COUNT=2
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2027, 3, 22, 9),
        DateTime.utc(2027, 3, 29, 8),
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

    test('drops instances from more than 30 days ago', () {
      final events = parse(
        _event('''
          DTSTART:20250101T100000Z
          RRULE:FREQ=YEARLY;COUNT=3
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc().year), [2027]);
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

  group('an old series', () {
    // Which day's instance is the first in range depends on the machine's
    // zone, so these check the cut-off rather than a fixed date.
    final rangeStart = now.subtract(const Duration(days: 30));
    const day = Duration(days: 1);

    List<DateTime> starts(String ics) =>
        parse(ics).map((e) => e.startTime.toUtc() as DateTime).toList();

    void expectFirstInRange(List<DateTime> starts) {
      expect(starts.first.isBefore(rangeStart), isFalse);
      expect(starts.first.subtract(day).isBefore(rangeStart), isTrue);
    }

    test('only yields instances from the last 30 days on', () {
      final daily = starts(
        _event('''
          DTSTART:20190101T100000Z
          RRULE:FREQ=DAILY
        '''),
      );
      expectFirstInRange(daily);
      expect(daily.first.hour, 10);
      for (var i = 1; i < daily.length; i++) {
        expect(daily[i].difference(daily[i - 1]), day);
      }
      // 30 days back to 180 ahead, not every day since 2019.
      expect(daily.length, inInclusiveRange(209, 211));
    });

    test('keeps a TZID series on its wall-clock time', () {
      // 9am in Berlin is 07:00Z in summer time, 08:00Z after 25 Oct.
      final daily = starts(
        _event('''
          DTSTART;TZID=Europe/Berlin:20190101T090000
          RRULE:FREQ=DAILY
        '''),
      );
      expectFirstInRange(daily);
      expect(daily.first.hour, 7);
      expect(daily, contains(DateTime.utc(2026, 10, 24, 7)));
      expect(daily, contains(DateTime.utc(2026, 10, 25, 8)));
    });

    test('counts COUNT from DTSTART, not from the range', () {
      // Instance 2850 of a daily series from 1 Jan 2019 is 20 Oct 2026.
      final daily = starts(
        _event('''
          DTSTART:20190101T100000Z
          RRULE:FREQ=DAILY;COUNT=2850
        '''),
      );
      expectFirstInRange(daily);
      expect(daily.last, DateTime.utc(2026, 10, 20, 10));
    });

    test('still honors EXDATE', () {
      final daily = starts(
        _event('''
          DTSTART:20190101T100000Z
          RRULE:FREQ=DAILY;COUNT=2850
          EXDATE:20261001T100000Z
        '''),
      );
      expect(daily, contains(DateTime.utc(2026, 9, 30, 10)));
      expect(daily, isNot(contains(DateTime.utc(2026, 10, 1, 10))));
      expect(daily, contains(DateTime.utc(2026, 10, 2, 10)));
    });
  });

  group('UNTIL', () {
    String utcStamp(DateTime moment) {
      final u = moment.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${u.year}${two(u.month)}${two(u.day)}'
          'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
    }

    test('a UTC UNTIL keeps the last instance east of UTC', () {
      // 15 Dec 09:00 in Berlin is 08:00Z, exactly UNTIL.
      final events = parse(
        _event('''
          DTSTART;TZID=Europe/Berlin:20261201T090000
          RRULE:FREQ=DAILY;UNTIL=20261215T080000Z
        '''),
      );
      final starts = events.map((e) => e.startTime.toUtc()).toList();
      expect(starts, hasLength(15));
      expect(starts.last, DateTime.utc(2026, 12, 15, 8));
    });

    test('a UTC UNTIL is read at its own offset across DST', () {
      // Berlin leaves summer time on 25 Oct: 9am on 2 Nov is 08:00Z.
      final events = parse(
        _event('''
          DTSTART;TZID=Europe/Berlin:20261020T090000
          RRULE:FREQ=DAILY;UNTIL=20261102T080000Z
        '''),
      );
      expect(events.last.startTime.toUtc(), DateTime.utc(2026, 11, 2, 8));
      expect(events, hasLength(14));
    });

    test('a UTC UNTIL ends the series on time west of UTC', () {
      // 8pm in Los Angeles is 04:00Z the next day. 03:00Z on 16 Dec is 7pm
      // on the 15th, an hour before that day's instance.
      List<DateTime> until(String value) => parse(
        _event('''
          DTSTART;TZID=America/Los_Angeles:20261201T200000
          RRULE:FREQ=DAILY;UNTIL=$value
        '''),
      ).map((e) => e.startTime.toUtc() as DateTime).toList();

      expect(until('20261216T030000Z').last, DateTime.utc(2026, 12, 15, 4));
      expect(until('20261216T040000Z').last, DateTime.utc(2026, 12, 16, 4));
    });

    test('a DATE UNTIL includes its day for an all-day series', () {
      final events = parse(
        _event('''
          DTSTART;VALUE=DATE:20261201
          RRULE:FREQ=DAILY;UNTIL=20261205
        '''),
      );
      expect(events.map((e) => e.date), [
        for (var day = 1; day <= 5; day++) DateTime(2026, 12, day),
      ]);
    });

    test('a DATE UNTIL includes its whole day for a timed series', () {
      final events = parse(
        _event('''
          DTSTART;TZID=Asia/Tokyo:20261201T230000
          RRULE:FREQ=DAILY;UNTIL=20261203
        '''),
      );
      expect(events.map((e) => e.startTime.toUtc()), [
        DateTime.utc(2026, 12, 1, 14),
        DateTime.utc(2026, 12, 2, 14),
        DateTime.utc(2026, 12, 3, 14),
      ]);
    });

    test('a UTC series ends at a UTC UNTIL', () {
      final events = parse(
        _event('''
          DTSTART:20261201T090000Z
          RRULE:FREQ=DAILY;UNTIL=20261203T090000Z
        '''),
      );
      expect(events.last.startTime.toUtc(), DateTime.utc(2026, 12, 3, 9));
      expect(events, hasLength(3));
    });

    test('a floating series ends at a floating UNTIL', () {
      final events = parse(
        _event('''
          DTSTART:20261201T090000
          RRULE:FREQ=DAILY;UNTIL=20261203T090000
        '''),
      );
      expect(events.map((e) => e.startTime), [
        DateTime(2026, 12, 1, 9),
        DateTime(2026, 12, 2, 9),
        DateTime(2026, 12, 3, 9),
      ]);
    });

    test('a floating series reads a UTC UNTIL on the local clock', () {
      // An hour before the 3 Dec instance, on this machine's clock.
      final until = utcStamp(DateTime(2026, 12, 3, 8));
      final events = parse(
        _event('''
          DTSTART:20261201T090000
          RRULE:FREQ=DAILY;UNTIL=$until
        '''),
      );
      expect(events.map((e) => e.startTime), [
        DateTime(2026, 12, 1, 9),
        DateTime(2026, 12, 2, 9),
      ]);
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
