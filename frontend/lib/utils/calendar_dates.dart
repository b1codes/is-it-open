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

/// The last day an all-day event from [start] to [end] covers. Device
/// calendars report the end either exclusively (midnight after the last day)
/// or inclusively (late on the last day, such as 23:59:59), so it's the day
/// before a midnight end and [end]'s day otherwise. Never before [start]'s
/// day: taking a day off every end put a same-day 23:59:59 end before the
/// event began, and the calendar drew it wrongly or not at all.
DateTime lastDayOfAllDayEvent(DateTime start, DateTime end) =>
    lastDayOfTimedEvent(start, end);

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
