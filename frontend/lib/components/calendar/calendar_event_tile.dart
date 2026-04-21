import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart';
import 'dart:math' as math;
import '../shared/glass_card.dart';

class CalendarEventTileWidget extends StatelessWidget {
  final DateTime date;
  final List<CalendarEventData<dynamic>> events;
  final Rect boundary;
  final DateTime startDuration;
  final DateTime endDuration;

  const CalendarEventTileWidget({
    super.key,
    required this.date,
    required this.events,
    required this.boundary,
    required this.startDuration,
    required this.endDuration,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final event = events[0];

    return GlassCard(
      color: event.color,
      opacity: 0.3,
      blur: 10,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: event.color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (event.description != null && event.description!.isNotEmpty)
                    Text(
                      event.description!,
                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FullDayEventWidget extends StatelessWidget {
  final List<CalendarEventData<dynamic>> events;
  final DateTime date;

  const FullDayEventWidget({
    super.key,
    required this.events,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: events.map((event) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: GlassCard(
              color: event.color,
              opacity: 0.3,
              blur: 10,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(4),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: event.color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomLeft: Radius.circular(4),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Text(
                          event.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class StackEventArranger<T extends Object?> extends EventArranger<T> {
  const StackEventArranger();

  @override
  List<OrganizedCalendarEventData<T>> arrange({
    required DateTime calendarViewDate,
    required List<CalendarEventData<T>> events,
    required double height,
    required double width,
    required double heightPerMinute,
    required int startHour,
  }) {
    final arrangedEvents = <OrganizedCalendarEventData<T>>[];

    for (final event in events) {
      final startTime = event.startTime ?? event.date;
      final endTime = event.endTime ?? event.date;

      final startOffset = (startTime.hour - startHour) * 60 + startTime.minute;
      final top = math.max(0.0, startOffset * heightPerMinute);

      var endOffset = (endTime.hour - startHour) * 60 + endTime.minute;
      var bottom = height - (endOffset * heightPerMinute);

      if (endTime.day != startTime.day || bottom > (height - top)) {
        bottom = 0.0;
      }

      arrangedEvents.add(
        OrganizedCalendarEventData<T>(
          calendarViewDate: calendarViewDate,
          startDuration: startTime,
          endDuration: endTime,
          top: top,
          bottom: bottom,
          left: 0.0,
          right: 0.0,
          events: [event],
        ),
      );
    }

    return arrangedEvents;
  }
}
