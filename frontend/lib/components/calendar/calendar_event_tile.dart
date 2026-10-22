import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart';
import 'dart:math' as math;
import '../../utils/places_theme.dart';

/// What a block in the week view is, carried in [CalendarEventData.event],
/// so tiles style it by what it is rather than by its color.
enum CalendarBlockKind { personal, openWindow }

extension on CalendarEventData<dynamic> {
  bool get isPersonal => event == CalendarBlockKind.personal;
}

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

    final isBusinessBlock = !event.isPersonal;

    return AnimatedContainer(
      duration: PlacesMotion.of(context, const Duration(milliseconds: 300)),
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
      // In ink rather than the block's color, which is 15% opaque.
      child: Text(
        event.title,
        style: PlacesType.label(
          context.places.ink,
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildPersonalBlock(BuildContext context, CalendarEventData event) {
    // White on a dark block; on a light one (dark mode's inkMuted), white
    // would be under 3:1.
    final textColor = PlacesTheme.onColor(
      Color.alphaBlend(
        event.color.withValues(alpha: 0.9),
        context.places.paper,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        event.title,
        style: PlacesType.label(
          textColor,
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
          final isBusinessBlock = !event.isPersonal;

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
                          // Not the 60%-opaque event color the block is
                          // tinted with, which was under 3:1.
                          style:
                              PlacesType.label(
                                isBusinessBlock
                                    ? theme.ink
                                    : PlacesTheme.onColor(
                                        Color.alphaBlend(
                                          event.color.withValues(alpha: 0.9),
                                          theme.paper,
                                        ),
                                      ),
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

    final day = DateTime(
      calendarViewDate.year,
      calendarViewDate.month,
      calendarViewDate.day,
    );
    final nextDay = DateTime(day.year, day.month, day.day + 1);

    for (final event in sortedEvents) {
      final startTime = event.startTime ?? event.date;
      final endTime = event.endTime ?? event.date;

      // An event spanning midnight is drawn on each of its days: from the
      // top of the days after its first, to the bottom of those before its
      // last.
      final startOffset = (startTime.hour - startHour) * 60 + startTime.minute;
      final top = startTime.isBefore(day)
          ? 0.0
          : math.max(0.0, startOffset * heightPerMinute);

      var endOffset = (endTime.hour - startHour) * 60 + endTime.minute;
      var bottom = height - (endOffset * heightPerMinute);

      if (!endTime.isBefore(nextDay) || bottom > (height - top)) {
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
