import 'package:timezone/timezone.dart' as tz;

class AvailabilityWindow {
  final DateTime date;
  final DateTime startTime;
  final DateTime endTime;
  final int placeCount;
  final List<String> placeIds;

  AvailabilityWindow({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.placeCount,
    this.placeIds = const [],
  });
}

class AvailabilityCalculator {
  /// Calculates consolidated windows where business hours and personal free time overlap.
  /// Uses [tz.local] for all time calculations to ensure consistency.
  static List<AvailabilityWindow> calculateAvailableWindows({
    required List<Map<String, dynamic>>
    businessBlocks, // {id, startTime, endTime}
    required List<Map<String, dynamic>> personalEvents, // {startTime, endTime}
  }) {
    if (businessBlocks.isEmpty) return [];

    List<AvailabilityWindow> results = [];

    // 1. Group by day using user's local timezone
    final blocksByDay = _groupByDay(businessBlocks);
    final personalByDay = _groupByDay(personalEvents);

    final sortedDates = blocksByDay.keys.toList()..sort();

    for (final date in sortedDates) {
      final dayBlocks = blocksByDay[date]!;
      final dayPersonal = personalByDay[date] ?? [];

      // 2. Find free chunks
      final freeChunks = _findFreeChunks(date, dayPersonal);

      // 3. Match businesses to chunks
      for (final chunk in freeChunks) {
        final chunkStart = chunk['start'] as DateTime;
        final chunkEnd = chunk['end'] as DateTime;

        final availableBusinesses = dayBlocks.where((b) {
          final bStart = b['startTime'] as DateTime;
          final bEnd = b['endTime'] as DateTime;
          return bStart.isBefore(chunkEnd) && bEnd.isAfter(chunkStart);
        }).toList();

        if (availableBusinesses.isNotEmpty) {
          final subWindows = _subdivideByBusinessHours(
            chunkStart,
            chunkEnd,
            availableBusinesses,
          );
          results.addAll(subWindows);
        }
      }
    }

    return results;
  }

  static Map<DateTime, List<Map<String, dynamic>>> _groupByDay(
    List<Map<String, dynamic>> items,
  ) {
    final Map<DateTime, List<Map<String, dynamic>>> grouped = {};
    for (final item in items) {
      final dt = item['startTime'] as DateTime;
      // Extract the wall-clock day
      final day = DateTime(dt.year, dt.month, dt.day);
      grouped.putIfAbsent(day, () => []).add(item);
    }
    return grouped;
  }

  static List<Map<String, DateTime>> _findFreeChunks(
    DateTime day,
    List<Map<String, dynamic>> personalEvents,
  ) {
    // Naive 6 AM to 11 PM
    final startOfDay = DateTime(day.year, day.month, day.day, 6);
    final endOfDay = DateTime(day.year, day.month, day.day, 23);

    final sortedEvents = List<Map<String, dynamic>>.from(personalEvents)
      ..sort((a, b) => (a['startTime'] as DateTime).compareTo(b['startTime']));

    List<Map<String, DateTime>> freeChunks = [];
    DateTime currentStart = startOfDay;

    for (final event in sortedEvents) {
      final eStart = event['startTime'] as DateTime;
      final eEnd = event['endTime'] as DateTime;

      if (eStart.isAfter(currentStart)) {
        freeChunks.add({
          'start': currentStart,
          'end': eStart.isBefore(endOfDay) ? eStart : endOfDay,
        });
      }
      if (eEnd.isAfter(currentStart)) {
        currentStart = eEnd;
      }
      if (currentStart.isAfter(endOfDay)) break;
    }

    if (currentStart.isBefore(endOfDay)) {
      freeChunks.add({'start': currentStart, 'end': endOfDay});
    }

    return freeChunks;
  }

  static List<AvailabilityWindow> _subdivideByBusinessHours(
    DateTime chunkStart,
    DateTime chunkEnd,
    List<Map<String, dynamic>> businesses,
  ) {
    final Set<DateTime> timestamps = {chunkStart, chunkEnd};
    for (final b in businesses) {
      final bStart = b['startTime'] as DateTime;
      final bEnd = b['endTime'] as DateTime;
      if (bStart.isAfter(chunkStart) && bStart.isBefore(chunkEnd)) {
        timestamps.add(bStart);
      }
      if (bEnd.isAfter(chunkStart) && bEnd.isBefore(chunkEnd)) {
        timestamps.add(bEnd);
      }
    }

    final sortedTimestamps = timestamps.toList()..sort();
    List<AvailabilityWindow> subWindows = [];

    for (int i = 0; i < sortedTimestamps.length - 1; i++) {
      final start = sortedTimestamps[i];
      final end = sortedTimestamps[i + 1];
      final mid = start.add(end.difference(start) ~/ 2);

      final activeBusinesses = businesses.where((b) {
        final bStart = b['startTime'] as DateTime;
        final bEnd = b['endTime'] as DateTime;
        return bStart.isBefore(mid) && bEnd.isAfter(mid);
      }).toList();

      if (activeBusinesses.isNotEmpty) {
        subWindows.add(
          AvailabilityWindow(
            date: DateTime(start.year, start.month, start.day),
            startTime: start,
            endTime: end,
            placeCount: activeBusinesses.length,
            placeIds: activeBusinesses.map((b) => b['id'] as String).toList(),
          ),
        );
      }
    }

    return subWindows;
  }
}
