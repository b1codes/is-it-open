import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../bloc/calendar/calendar_ui_state.dart';
import '../../bloc/calendar/calendar_ui_cubit.dart';
import '../../utils/places_theme.dart';
import 'calendar_event_tile.dart';
import 'calendar_header.dart';
import 'event_details_popup.dart';

String _weekDayShortName(int weekday) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[weekday - 1];
}

Widget _buildTimeLineLabel(
  DateTime date,
  bool use24HourFormat,
  Color labelColor,
) {
  final timeString = use24HourFormat
      ? "${date.hour.toString().padLeft(2, '0')}:00"
      : DateFormat(
          'h a',
        ).format(DateTime(date.year, date.month, date.day, date.hour));

  final textStyle = PlacesType.label(
    labelColor,
  ).copyWith(fontSize: 11, letterSpacing: 0, fontWeight: FontWeight.w500);

  final label = Center(child: Text(timeString, style: textStyle));

  if (date.hour == 1) {
    final midnightString = use24HourFormat ? '00:00' : '12 AM';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        label,
        Positioned(
          top: -60,
          height: 60,
          left: 0,
          right: 0,
          child: Center(child: Text(midnightString, style: textStyle)),
        ),
      ],
    );
  }
  return label;
}

class CalendarViewStackWidget extends StatelessWidget {
  final CalendarUiState uiState;
  final EventController<Object?> controller;
  final int checkedPlacesCount;
  final Color textColor;
  final Color textSmallColor;
  final bool use24HourFormat;

  const CalendarViewStackWidget({
    super.key,
    required this.uiState,
    required this.controller,
    required this.checkedPlacesCount,
    required this.textColor,
    required this.textSmallColor,
    required this.use24HourFormat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.places;

    List<WeekDays> weekDays = WeekDays.values;
    int daysToAdvance = 0;

    if (uiState.currentView == CalendarViewType.threeDay) {
      daysToAdvance = 3;
      weekDays = [
        WeekDays.values[uiState.baseDate.weekday - 1],
        WeekDays.values[uiState.baseDate.add(const Duration(days: 1)).weekday -
            1],
        WeekDays.values[uiState.baseDate.add(const Duration(days: 2)).weekday -
            1],
      ];
    } else if (uiState.currentView == CalendarViewType.singleDay) {
      daysToAdvance = 1;
    } else {
      daysToAdvance = 7;
    }

    final now = tz.TZDateTime.now(tz.local);
    final initialScrollOffset = (now.hour * 60.0 + now.minute) * 1.0;
    final isShowingToday =
        DateUtils.isSameDay(uiState.baseDate, now) ||
        (uiState.currentView == CalendarViewType.week &&
            uiState.baseDate
                .subtract(Duration(days: uiState.baseDate.weekday - 1))
                .isBefore(now) &&
            uiState.baseDate
                .subtract(Duration(days: uiState.baseDate.weekday - 1))
                .add(const Duration(days: 7))
                .isAfter(now));

    Widget calendarWidget;
    if (uiState.currentView == CalendarViewType.singleDay) {
      calendarWidget = DayView(
        key: ValueKey('day_${uiState.baseDate}_$checkedPlacesCount'),
        controller: controller,
        initialDay: uiState.baseDate,
        scrollOffset: initialScrollOffset,
        minDay: uiState.baseDate.subtract(const Duration(days: 28)),
        maxDay: uiState.baseDate.add(const Duration(days: 84)),
        heightPerMinute: 1.2,
        scrollPhysics: const ClampingScrollPhysics(),
        pageViewPhysics: const NeverScrollableScrollPhysics(),
        backgroundColor: theme.paper,
        headerStyle: HeaderStyle(decoration: BoxDecoration(color: theme.paper)),
        eventArranger: const StackEventArranger(),
        eventTileBuilder:
            (date, events, boundary, startDuration, endDuration) =>
                CalendarEventTileWidget(
                  date: date,
                  events: events,
                  boundary: boundary,
                  startDuration: startDuration,
                  endDuration: endDuration,
                ),
        onEventTap: (events, date) {
          if (events.isNotEmpty) {
            showDialog(
              context: context,
              builder: (context) => EventDetailsPopup(event: events.first),
            );
          }
        },
        fullDayEventBuilder: (events, date) => const SizedBox.shrink(),
        showLiveTimeLineInAllDays: true,
        dayTitleBuilder: (date) {
          final dayEvents = controller.getEventsOnDay(date);
          final allDayEvents = dayEvents
              .where((e) => e.startTime == null || e.endTime == null)
              .toList();
          final hasAllDay = allDayEvents.isNotEmpty;

          if (!hasAllDay) return const SizedBox.shrink();

          return Semantics(
            button: true,
            label: 'Show all day events',
            child: GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: theme.paper,
                  builder: (context) =>
                      _AllDayEventsSheet(date: date, events: allDayEvents),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                color: theme.anchor.withValues(alpha: 0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_note, size: 16, color: theme.anchor),
                    const SizedBox(width: 8),
                    Text(
                      '${allDayEvents.length} All-Day Event(s)',
                      style: PlacesType.label(
                        theme.anchor,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        hourIndicatorSettings: HourIndicatorSettings(color: theme.ashSoft),
        liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
          color: theme.anchor,
        ),
        timeLineBuilder: (date) =>
            _buildTimeLineLabel(date, use24HourFormat, textSmallColor),
      );
    } else {
      calendarWidget = WeekView(
        key: ValueKey(
          'week_${uiState.baseDate}_${uiState.currentView}_$checkedPlacesCount',
        ),
        controller: controller,
        minDay: uiState.baseDate.subtract(const Duration(days: 28)),
        maxDay: uiState.baseDate.add(const Duration(days: 84)),
        initialDay: uiState.baseDate,
        scrollOffset: initialScrollOffset,
        startDay: uiState.currentView == CalendarViewType.threeDay
            ? WeekDays.values[uiState.baseDate.weekday - 1]
            : WeekDays.monday,
        weekDays: weekDays,
        heightPerMinute: 1.2,
        scrollPhysics: const ClampingScrollPhysics(),
        pageViewPhysics: const NeverScrollableScrollPhysics(),
        backgroundColor: theme.paper,
        headerStyle: HeaderStyle(decoration: BoxDecoration(color: theme.paper)),
        weekTitleBackgroundColor: theme.paper,
        eventArranger: const StackEventArranger(),
        eventTileBuilder:
            (date, events, boundary, startDuration, endDuration) =>
                CalendarEventTileWidget(
                  date: date,
                  events: events,
                  boundary: boundary,
                  startDuration: startDuration,
                  endDuration: endDuration,
                ),
        onEventTap: (events, date) {
          if (events.isNotEmpty) {
            showDialog(
              context: context,
              builder: (context) => EventDetailsPopup(event: events.first),
            );
          }
        },
        fullDayEventBuilder: (events, date) => const SizedBox.shrink(),
        showLiveTimeLineInAllDays: true,
        weekPageHeaderBuilder: (start, end) => const SizedBox.shrink(),
        weekNumberBuilder: (date) => const SizedBox.shrink(),
        hourIndicatorSettings: HourIndicatorSettings(color: theme.ashSoft),
        liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
          color: theme.anchor,
          showBullet: false,
        ),
        timeLineBuilder: (date) =>
            _buildTimeLineLabel(date, use24HourFormat, textSmallColor),
        weekDayBuilder: (date) {
          final isToday = DateUtils.isSameDay(date, tz.TZDateTime.now(tz.local));
          final dayEvents = controller.getEventsOnDay(date);
          final allDayEvents = dayEvents
              .where((e) => e.startTime == null || e.endTime == null)
              .toList();
          final hasAllDay = allDayEvents.isNotEmpty;

          return Semantics(
            button: hasAllDay,
            label: hasAllDay ? 'Show all day events' : null,
            child: GestureDetector(
              onTap: () {
                if (hasAllDay) {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: theme.paper,
                    builder: (context) =>
                        _AllDayEventsSheet(date: date, events: allDayEvents),
                  );
                }
              },
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ), // Reduced from 6 to 4 to fix overflow
                  decoration: isToday
                      ? BoxDecoration(
                          color: theme.anchor,
                          borderRadius: BorderRadius.circular(8),
                        )
                      : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _weekDayShortName(date.weekday).toUpperCase(),
                        style:
                            PlacesType.label(
                              isToday ? Colors.white : textColor,
                            ).copyWith(
                              fontSize: 10,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${date.day}',
                            style:
                                PlacesType.title(
                                  isToday ? Colors.white : textColor,
                               ).copyWith(
                                  fontSize: 15,
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                          ),
                          if (hasAllDay) ...[
                            const SizedBox(width: 4),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isToday ? Colors.white : theme.anchor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                color: textColor,
                onPressed: () {
                  context.read<CalendarUiCubit>().navigateDate(
                    uiState.baseDate.subtract(Duration(days: daysToAdvance)),
                  );
                },
              ),
              Expanded(
                child: Text(
                  buildCalendarHeaderText(
                    uiState.currentView,
                    uiState.baseDate,
                  ),
                  textAlign: TextAlign.center,
                  style: PlacesType.title(textColor),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                color: textColor,
                onPressed: () {
                  context.read<CalendarUiCubit>().navigateDate(
                    uiState.baseDate.add(Duration(days: daysToAdvance)),
                  );
                },
              ),
              if (!isShowingToday)
                TextButton(
                  onPressed: () => context.read<CalendarUiCubit>().navigateDate(
                    tz.TZDateTime.now(tz.local),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.anchor,
                    textStyle: PlacesType.label(
                      theme.anchor,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Today'),
                ),
            ],
          ),
        ),
        Expanded(
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                secondaryContainer: theme.paper,
                primaryContainer: theme.paper,
                surface: theme.paper,
                error: Colors.transparent,
              ),
              canvasColor: theme.paper,
              cardColor: theme.paper,
              secondaryHeaderColor: theme.paper,
            ),
            child: calendarWidget,
          ),
        ),
      ],
    );
  }
}

class _AllDayEventsSheet extends StatelessWidget {
  final DateTime date;
  final List<CalendarEventData<Object?>> events;

  const _AllDayEventsSheet({required this.date, required this.events});

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All-Day Events for ${date.month}/${date.day}',
            style: PlacesType.headline(theme.ink),
          ),
          const SizedBox(height: 24),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: event.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          event.title,
                          style: PlacesType.body(theme.ink),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
