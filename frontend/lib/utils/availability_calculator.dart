import 'package:calendar_view/calendar_view.dart';

class AvailabilityCalculator {
  static List<CalendarEventData<Object?>> calculateAvailableWindows(
    List<CalendarEventData<Object?>> businessBlocks,
    List<CalendarEventData<Object?>> personalEvents,
  ) {
    List<CalendarEventData<Object?>> results = [];

    // Sort personal events by start time
    final sortedPersonal = List<CalendarEventData<Object?>>.from(personalEvents)
      ..sort((a, b) => (a.startTime ?? a.date).compareTo(b.startTime ?? b.date));

    for (final businessBlock in businessBlocks) {
      DateTime currentStart = businessBlock.startTime ?? businessBlock.date;
      DateTime finalEnd = businessBlock.endTime ?? businessBlock.date;

      for (final personalEvent in sortedPersonal) {
        // Only consider personal events on the same day for this simplified logic
        if (personalEvent.date.year != businessBlock.date.year ||
            personalEvent.date.month != businessBlock.date.month ||
            personalEvent.date.day != businessBlock.date.day) {
          continue;
        }
        
        // Skip all-day events in this specific time-based subtraction
        if (personalEvent.startTime == null || personalEvent.endTime == null) {
            continue;
        }

        final pStart = personalEvent.startTime!;
        final pEnd = personalEvent.endTime!;

        // Overlap check
        if (pStart.isBefore(finalEnd) && pEnd.isAfter(currentStart)) {
          // If there's a gap before the personal event starts, that's an available window
          if (pStart.isAfter(currentStart)) {
            results.add(
              CalendarEventData(
                title: businessBlock.title,
                date: businessBlock.date,
                startTime: currentStart,
                endTime: pStart,
                color: businessBlock.color,
              ),
            );
          }
          // Move the current start to the end of the personal event (or keep it if personal event ends earlier)
          if (pEnd.isAfter(currentStart)) {
             currentStart = pEnd;
          }
        }
      }

      // Add the remaining time as an available window
      if (currentStart.isBefore(finalEnd)) {
        results.add(
          CalendarEventData(
            title: businessBlock.title,
            date: businessBlock.date,
            startTime: currentStart,
            endTime: finalEnd,
            color: businessBlock.color,
          ),
        );
      }
    }

    return results;
  }
}
