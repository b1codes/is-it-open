import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../utils/calendar_dates.dart';

class IcalParserService {
  /// How far back and ahead of now a repeating event is expanded. Only the
  /// expanded instances are kept, so a week the calendar is moved to outside
  /// this range shows none of a series' instances (one-off events show at
  /// any date). A year back covers looking back over recent months without
  /// a daily series since 2019 turning into thousands of instances.
  static const recurrenceLookback = Duration(days: 365);
  static const recurrenceLookahead = Duration(days: 180);

  static const Map<String, String> _tzidMap = {
    'Eastern Standard Time': 'America/New_York',
    'Eastern Day Time': 'America/New_York',
    'Eastern Time': 'America/New_York',
    'Central Standard Time': 'America/Chicago',
    'Central Day Time': 'America/Chicago',
    'Central Time': 'America/Chicago',
    'Mountain Standard Time': 'America/Denver',
    'Mountain Day Time': 'America/Denver',
    'Mountain Time': 'America/Denver',
    'Pacific Standard Time': 'America/Los_Angeles',
    'Pacific Day Time': 'America/Los_Angeles',
    'Pacific Time': 'America/Los_Angeles',
    'GMT Standard Time': 'Europe/London',
    'W. Europe Standard Time': 'Europe/Berlin',
    'Central Europe Standard Time': 'Europe/Prague',
    'India Standard Time': 'Asia/Kolkata',
    'China Standard Time': 'Asia/Shanghai',
    'Tokyo Standard Time': 'Asia/Tokyo',
  };

  List<CalendarEventData<Object?>> parse(
    String icsString, {
    Color eventColor = Colors.blue,
  }) {
    final sanitizedIcsString = icsString.replaceAllMapped(
      RegExp(r'^(RRULE:.*)$', multiLine: true),
      (match) {
        final line = match.group(1)!;
        return line
            .split(';')
            .where((part) => !part.toUpperCase().startsWith('WKST='))
            .join(';');
      },
    );

    final iCalendar = ICalendar.fromString(sanitizedIcsString);
    final List<CalendarEventData<Object?>> events = [];

    for (final entry in iCalendar.data) {
      if (entry['type'] == 'VEVENT') {
        events.addAll(_processEvent(entry, eventColor));
      }
    }
    return events;
  }

  String _normalizeTzid(String tzid) {
    var clean = tzid.replaceAll('"', '').trim();
    return _tzidMap[clean] ?? clean;
  }

  /// Reads a DTSTART/DTEND/EXDATE value, keeping the wall-clock time and
  /// the zone it is written in so recurrences can be expanded there.
  _IcsTime? _parseIcsDateTime(IcsDateTime? icsDateTime) {
    if (icsDateTime == null) return null;

    final String dtString = icsDateTime.dt;
    final String? tzid = icsDateTime.tzid;
    final cleanDt = dtString.replaceAll(RegExp(r'[-:]'), '');

    // 1. All-day events (e.g., 20260517)
    if (cleanDt.length == 8 && !cleanDt.contains('T')) {
      final date = _parseDigits(cleanDt, [(0, 4), (4, 6), (6, 8)]);
      if (date == null) return null;
      return _IcsTime(DateTime.utc(date[0], date[1], date[2]), _IcsZone.allDay);
    }

    // 2. Extract common components
    if (cleanDt.length < 15) return null;
    final parts = _parseDigits(cleanDt, [
      (0, 4),
      (4, 6),
      (6, 8),
      (9, 11),
      (11, 13),
      (13, 15),
    ]);
    if (parts == null) return null;
    final wall = DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5],
    );

    // 3. UTC time (Z)
    if (cleanDt.endsWith('Z')) return _IcsTime(wall, _IcsZone.utc);

    // 4. Time in a named zone. An unknown zone falls back to floating time.
    if (tzid != null) {
      try {
        final location = tz.getLocation(_normalizeTzid(tzid));
        return _IcsTime(wall, _IcsZone.named, location);
      } catch (_) {
        return _IcsTime(wall, _IcsZone.floating);
      }
    }

    // 5. Floating local time
    return _IcsTime(wall, _IcsZone.floating);
  }

  static List<int>? _parseDigits(String s, List<(int, int)> ranges) {
    try {
      return [for (final (a, b) in ranges) int.parse(s.substring(a, b))];
    } catch (_) {
      return null;
    }
  }

  List<CalendarEventData<Object?>> _processEvent(
    Map<String, dynamic> entry,
    Color color,
  ) {
    final title = entry['summary'] ?? 'Event';
    final dtstartIcs = entry['dtstart'] as IcsDateTime?;
    final dtendIcs = entry['dtend'] as IcsDateTime?;
    final description = entry['description'];
    final rruleString = entry['rrule'] as String?;

    final start = _parseIcsDateTime(dtstartIcs);
    if (start == null) return [];
    final isAllDay = start.zone == _IcsZone.allDay;

    // The event's length on its own wall clock, so each recurrence keeps it.
    // DTEND can be in another zone (a flight's arrival); it's read on the
    // start's clock first, or the difference of the two wall clocks is off
    // by the zones' offset.
    final end = _parseIcsDateTime(dtendIcs);
    final endWall = end == null || end.sameClockAs(start)
        ? end?.wall
        : start.wallOf(end.toLocal());
    final Duration duration;
    if (endWall != null && endWall.isAfter(start.wall)) {
      duration = endWall.difference(start.wall);
    } else {
      duration = isAllDay ? const Duration(days: 1) : const Duration(hours: 1);
    }

    if (rruleString != null && rruleString.isNotEmpty) {
      final sanitizedRrule = rruleString
          .split(';')
          .where((part) => !part.toUpperCase().startsWith('WKST='))
          .join(';');

      try {
        final rule = _untilOnWallClock(
          RecurrenceRule.fromString('RRULE:$sanitizedRrule'),
          sanitizedRrule,
          start,
        );
        final nowLocal = clock.now();
        final defaultRangeStart = nowLocal.subtract(recurrenceLookback);
        final firstStart = start.toLocal();
        // Instances from a year ago on, or from the first one if later.
        final rangeStart = firstStart.isAfter(defaultRangeStart)
            ? firstStart
            : defaultRangeStart;
        final rangeEnd = nowLocal.add(recurrenceLookahead);
        final excluded = _exdates(entry);

        // rrule still iterates from DTSTART, so COUNT and the rule's phase
        // are kept, but only yields instances from `after` on, so an old
        // series doesn't convert years of past instances. `after` is a day
        // early so a DST change can't drop one; the rangeStart check below
        // is the exact cut.
        final after = start
            .wallOf(rangeStart)
            .subtract(const Duration(days: 1));

        // Expand on the event's own wall clock (RFC 5545 3.3.10), so a 9am
        // meeting in a named zone stays at 9am there across DST changes.
        // rrule only accepts UTC DateTimes, which here just carry the
        // wall-clock fields.
        final events = <CalendarEventData<Object?>>[];
        final walls = rule.getInstances(
          start: start.wall,
          after: after.isAfter(start.wall) ? after : null,
          includeAfter: true,
        );
        for (final wall in walls) {
          final instance = start.withWall(wall);
          final instanceStart = instance.toLocal();
          if (!instanceStart.isBefore(rangeEnd)) break;
          if (instanceStart.isBefore(rangeStart)) continue;
          if (excluded.any(instance.sameMomentAs)) continue;
          events.add(
            _createEventData(
              title: title,
              start: instanceStart,
              end: start.withWall(wall.add(duration)).toLocal(),
              description: description,
              color: color,
              isAllDay: isAllDay,
            ),
          );
        }
        return events;
      } catch (e) {
        debugPrint('Error parsing RRULE ($rruleString): $e');
      }
    }

    return [
      _createEventData(
        title: title,
        start: start.toLocal(),
        end: start.withWall(start.wall.add(duration)).toLocal(),
        description: description,
        color: color,
        isAllDay: isAllDay,
      ),
    ];
  }

  /// rrule stops at the first instance whose wall-clock fields are past
  /// UNTIL. RFC 5545 writes UNTIL in UTC when DTSTART has a zone (Google and
  /// Outlook write the last instance's UTC time), so it is moved onto the
  /// event's wall clock first; otherwise zones east of UTC lose their last
  /// instance and zones west of it can gain one. A DATE-only UNTIL on a
  /// timed event includes that whole day.
  RecurrenceRule _untilOnWallClock(
    RecurrenceRule rule,
    String rrule,
    _IcsTime start,
  ) {
    final until = rule.until;
    if (until == null || start.zone == _IcsZone.allDay) return rule;
    final match = RegExp(
      r'(?:^|;)UNTIL=\d{8}(T\d{6})?(Z)?(?:;|$)',
      caseSensitive: false,
    ).firstMatch(rrule);
    if (match == null) return rule;
    if (match.group(1) == null) {
      return rule.copyWith(
        until: DateTime.utc(until.year, until.month, until.day, 23, 59, 59),
      );
    }
    if (match.group(2) == null || start.zone == _IcsZone.utc) return rule;
    return rule.copyWith(until: start.wallOf(until));
  }

  List<_IcsTime> _exdates(Map<String, dynamic> entry) {
    final raw = entry['exdate'];
    if (raw is! List) return const [];
    return [
      for (final value in raw.whereType<IcsDateTime>())
        ?_parseIcsDateTime(value),
    ];
  }

  CalendarEventData<Object?> _createEventData({
    required String title,
    required DateTime start,
    required DateTime end,
    String? description,
    required Color color,
    required bool isAllDay,
  }) {
    // Strip metadata, return pure, un-shiftable naive wall-clock time
    final naiveStart = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
      start.second,
    );
    final naiveEnd = DateTime(
      end.year,
      end.month,
      end.day,
      end.hour,
      end.minute,
      end.second,
    );

    // DTEND is exclusive for all-day events: a one-day event ends the next
    // day at midnight, so the last day it covers is the one before. A timed
    // event that runs past midnight covers each day up to its end, so the
    // calendar draws the part after midnight on the next day.
    final lastDay = isAllDay
        ? DateTime(end.year, end.month, end.day - 1)
        : lastDayOfTimedEvent(naiveStart, naiveEnd);

    return CalendarEventData(
      title: title,
      date: naiveStart,
      endDate: lastDay.isBefore(naiveStart) ? naiveStart : lastDay,
      startTime: isAllDay ? null : naiveStart,
      endTime: isAllDay ? null : naiveEnd,
      description: description,
      color: color,
    );
  }
}

enum _IcsZone { allDay, floating, utc, named }

/// A date or date-time as written in the file: its wall-clock fields (held
/// in a UTC [DateTime]) plus the zone they are read in.
class _IcsTime {
  const _IcsTime(this.wall, this.zone, [this.location]);

  final DateTime wall;
  final _IcsZone zone;
  final tz.Location? location;

  _IcsTime withWall(DateTime wall) => _IcsTime(wall, zone, location);

  /// Whether [other]'s wall-clock fields are on this time's clock. Dates
  /// count as one clock, so an all-day DTEND on a timed DTSTART (which
  /// RFC 5545 doesn't allow) still reads as before.
  bool sameClockAs(_IcsTime other) =>
      zone == other.zone && location?.name == other.location?.name ||
      zone == _IcsZone.allDay ||
      other.zone == _IcsZone.allDay;

  /// The moment on the device's clock.
  DateTime toLocal() {
    switch (zone) {
      case _IcsZone.utc:
        return wall.toLocal();
      case _IcsZone.named:
        final source = tz.TZDateTime(
          location!,
          wall.year,
          wall.month,
          wall.day,
          wall.hour,
          wall.minute,
          wall.second,
        );
        return DateTime.fromMillisecondsSinceEpoch(
          source.millisecondsSinceEpoch,
        );
      case _IcsZone.allDay:
      case _IcsZone.floating:
        return DateTime(
          wall.year,
          wall.month,
          wall.day,
          wall.hour,
          wall.minute,
          wall.second,
        );
    }
  }

  /// The wall-clock fields [moment] has on this time's clock, held in a UTC
  /// [DateTime] like [wall].
  DateTime wallOf(DateTime moment) {
    final fields = switch (zone) {
      _IcsZone.utc => moment.toUtc(),
      _IcsZone.named => tz.TZDateTime.from(moment, location!),
      _IcsZone.allDay || _IcsZone.floating => moment.toLocal(),
    };
    return DateTime.utc(
      fields.year,
      fields.month,
      fields.day,
      fields.hour,
      fields.minute,
      fields.second,
    );
  }

  /// Whether an EXDATE value names this occurrence. All-day values match by
  /// date; others match the same instant, whatever zone each is written in.
  bool sameMomentAs(_IcsTime other) {
    if (zone == _IcsZone.allDay || other.zone == _IcsZone.allDay) {
      return wall.year == other.wall.year &&
          wall.month == other.wall.month &&
          wall.day == other.wall.day;
    }
    return toLocal().isAtSameMomentAs(other.toLocal());
  }
}
