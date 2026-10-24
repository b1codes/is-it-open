/// The last day a timed event from [start] to [end] shows on in the
/// calendar: [end]'s day, or the day before when it ends exactly at
/// midnight, so 22:00-00:00 stays a one-day event. Never before [start]'s
/// day.
DateTime lastDayOfTimedEvent(DateTime start, DateTime end) {
  final startDay = DateTime(start.year, start.month, start.day);
  // Compared by field: a TZDateTime (device calendars) never equals a
  // DateTime.
  final endsAtMidnight =
      end.hour == 0 &&
      end.minute == 0 &&
      end.second == 0 &&
      end.millisecond == 0 &&
      end.microsecond == 0;
  final lastDay = DateTime(
    end.year,
    end.month,
    end.day - (endsAtMidnight ? 1 : 0),
  );
  return lastDay.isBefore(startDay) ? startDay : lastDay;
}

/// [date] moved by [days] calendar days, at the same wall-clock time.
/// Adding `Duration(days: n)` adds n × 24 hours instead, which across a DST
/// change lands an hour off: on the same day again, or a day too far.
DateTime addCalendarDays(DateTime date, int days) => DateTime(
  date.year,
  date.month,
  date.day + days,
  date.hour,
  date.minute,
  date.second,
  date.millisecond,
  date.microsecond,
);
