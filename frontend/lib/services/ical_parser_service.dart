import 'package:flutter/material.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart' as tz;

class IcalParserService {
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

  /// Parses to a native Dart DateTime, ensuring strict OS-level timezone accuracy.
  DateTime? _parseIcsDateTime(IcsDateTime? icsDateTime) {
    if (icsDateTime == null) return null;

    final String dtString = icsDateTime.dt;
    final String? tzid = icsDateTime.tzid;
    final cleanDt = dtString.replaceAll(RegExp(r'[-:]'), '');

    // 1. All-Day events (e.g., 20260517)
    if (cleanDt.length == 8 && !cleanDt.contains('T')) {
      try {
        final year = int.parse(cleanDt.substring(0, 4));
        final month = int.parse(cleanDt.substring(4, 6));
        final day = int.parse(cleanDt.substring(6, 8));
        return DateTime(year, month, day); // Native local floating date
      } catch (_) {
        return null;
      }
    }

    // 2. Extract common components
    if (cleanDt.length < 15) return null;
    int year, month, day, hour, minute, second;
    try {
      year = int.parse(cleanDt.substring(0, 4));
      month = int.parse(cleanDt.substring(4, 6));
      day = int.parse(cleanDt.substring(6, 8));
      hour = int.parse(cleanDt.substring(9, 11));
      minute = int.parse(cleanDt.substring(11, 13));
      second = int.parse(cleanDt.substring(13, 15));
    } catch (_) {
      return null;
    }

    // 3. UTC Time (Z) -> Native OS Local
    if (cleanDt.endsWith('Z')) {
      return DateTime.utc(year, month, day, hour, minute, second).toLocal();
    }

    // 4. Time with TZID -> Absolute epoch -> Native OS Local
    if (tzid != null) {
      final normalizedTzid = _normalizeTzid(tzid);
      try {
        final location = tz.getLocation(normalizedTzid);
        final sourceTz = tz.TZDateTime(
          location,
          year,
          month,
          day,
          hour,
          minute,
          second,
        );
        return DateTime.fromMillisecondsSinceEpoch(
          sourceTz.millisecondsSinceEpoch,
        ).toLocal();
      } catch (e) {
        // Fallback: assume the time written is local wall-clock
        return DateTime(year, month, day, hour, minute, second);
      }
    }

    // 5. Floating Local Time
    return DateTime(year, month, day, hour, minute, second);
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

    if (dtstartIcs == null) return [];

    final start = _parseIcsDateTime(dtstartIcs);
    if (start == null) return [];

    final bool isAllDay =
        dtstartIcs.dt.length == 8 && !dtstartIcs.dt.contains('T');

    DateTime end;
    if (dtendIcs != null) {
      end = _parseIcsDateTime(dtendIcs) ?? start.add(const Duration(hours: 1));
    } else {
      end = isAllDay
          ? start.add(const Duration(days: 1))
          : start.add(const Duration(hours: 1));
    }

    final duration = end.difference(start);

    if (rruleString != null && rruleString.isNotEmpty) {
      final sanitizedRrule = rruleString
          .split(';')
          .where((part) => !part.toUpperCase().startsWith('WKST='))
          .join(';');

      try {
        final rule = RecurrenceRule.fromString('RRULE:$sanitizedRrule');
        final nowLocal = DateTime.now();
        final rangeStart = nowLocal.subtract(const Duration(days: 30));
        final rangeEnd = nowLocal.add(const Duration(days: 180));

        final instances = rule
            .getInstances(start: start.toUtc())
            .takeWhile((date) => date.isBefore(rangeEnd.toUtc()))
            .map((date) {
              if (isAllDay) return DateTime(date.year, date.month, date.day);
              // Native OS Local conversion
              return date.toLocal();
            })
            .where(
              (date) =>
                  date.isAfter(rangeStart) || date.isAtSameMomentAs(rangeStart),
            )
            .toList();

        return instances.map((instanceStart) {
          return _createEventData(
            title: title,
            start: instanceStart,
            end: instanceStart.add(duration),
            description: description,
            color: color,
            isAllDay: isAllDay,
          );
        }).toList();
      } catch (e) {
        debugPrint('Error parsing RRULE ($rruleString): $e');
      }
    }

    return [
      _createEventData(
        title: title,
        start: start,
        end: end,
        description: description,
        color: color,
        isAllDay: isAllDay,
      ),
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

    return CalendarEventData(
      title: title,
      date: naiveStart,
      startTime: isAllDay ? null : naiveStart,
      endTime: isAllDay ? null : naiveEnd,
      description: description,
      color: color,
    );
  }
}
