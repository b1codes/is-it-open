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
