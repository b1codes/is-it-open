import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart';
import 'dart:math' as math;
import '../../utils/places_theme.dart';

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

    // Heuristic: Business blocks are distinct from personal events based on the color assignment in the controller.
    // Personal events are assigned theme.inkMuted (set in CalendarScreen).
    final theme = context.places;
    final isPersonalEvent = event.color == theme.inkMuted;
    final isBusinessBlock = !isPersonalEvent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isBusinessBlock
            ? event.color.withValues(alpha: 0.15)
            : event.color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: isBusinessBlock
              ? event.color.withValues(alpha: 0.5)
              : event.color,
          width: 1.5,
        ),
      ),
      child: isBusinessBlock
          ? _buildBusinessBlock(context, event)
          : _buildPersonalBlock(context, event),
    );
  }

  Widget _buildBusinessBlock(BuildContext context, CalendarEventData event) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        event.title,
        style: PlacesType.label(
          event.color,
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildPersonalBlock(BuildContext context, CalendarEventData event) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        event.title,
        style: PlacesType.label(
          Colors.white,
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
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
    final theme = context.places;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: events.map((event) {
          final isPersonalEvent = event.color == theme.inkMuted;
          final isBusinessBlock = !isPersonalEvent;

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              decoration: BoxDecoration(
                color: isBusinessBlock
                    ? event.color.withValues(alpha: 0.15)
                    : event.color.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isBusinessBlock
                      ? event.color.withValues(alpha: 0.5)
                      : event.color,
                  width: 1,
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: event.color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(3),
                          bottomLeft: Radius.circular(3),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          event.title,
                          style:
                              PlacesType.label(
                                isBusinessBlock ? event.color : Colors.white,
                              ).copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
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

    // Ensure 'Open' is rendered first (background), and 'Planned Visit' last (top).
    final sortedEvents = List<CalendarEventData<T>>.from(events)
      ..sort((a, b) {
        // 'Open' always first
        if (a.title == 'Open' && b.title != 'Open') return -1;
        if (a.title != 'Open' && b.title == 'Open') return 1;

        // 'Planned Visit' always last
        if (a.title == 'Planned Visit' && b.title != 'Planned Visit') return 1;
        if (a.title != 'Planned Visit' && b.title == 'Planned Visit') return -1;

        return 0;
      });

    for (final event in sortedEvents) {
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
