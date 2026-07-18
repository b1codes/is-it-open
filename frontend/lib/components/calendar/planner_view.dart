import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../utils/places_theme.dart';
import '../../utils/availability_calculator.dart';

class PlannerView extends StatelessWidget {
  final DateTime baseDate;
  final int dayCount;
  final List<AvailabilityWindow> windows;
  final List<Map<String, dynamic>> personalEvents;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateRight;
  final VoidCallback onNavigateToday;
  final Function(AvailabilityWindow) onWindowTap;

  const PlannerView({
    super.key,
    required this.baseDate,
    required this.dayCount,
    required this.windows,
    required this.personalEvents,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    required this.onNavigateToday,
    required this.onWindowTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final isTodayVisible = _isTodayVisible();

    return Column(
      children: [
        _buildHeader(context, theme, isTodayVisible),
        Expanded(
          child: _PlannerTimeline(
            baseDate: baseDate,
            dayCount: dayCount,
            windows: windows,
            personalEvents: personalEvents,
            onWindowTap: onWindowTap,
          ),
        ),
      ],
    );
  }

  bool _isTodayVisible() {
    final now = tz.TZDateTime.now(tz.local);
    final today = tz.TZDateTime(tz.local, now.year, now.month, now.day);
    for (int i = 0; i < dayCount; i++) {
      final date = baseDate.add(Duration(days: i));
      if (tz.TZDateTime(tz.local, date.year, date.month, date.day) == today)
        return true;
    }
    return false;
  }

  Widget _buildHeader(
    BuildContext context,
    PlacesTheme theme,
    bool isTodayVisible,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: theme.ink,
            onPressed: onNavigateLeft,
          ),
          Expanded(
            child: Text(
              _getHeaderText(),
              textAlign: TextAlign.center,
              style: PlacesType.title(theme.ink),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: theme.ink,
            onPressed: onNavigateRight,
          ),
          if (!isTodayVisible)
            TextButton(
              onPressed: onNavigateToday,
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
    );
  }

  String _getHeaderText() {
    final start = baseDate;
    final end = baseDate.add(Duration(days: dayCount - 1));
    if (dayCount == 1) {
      return DateFormat('EEEE, MMM d').format(start);
    }
    if (start.month == end.month) {
      return "${DateFormat('MMM d').format(start)} – ${end.day}";
    }
    return "${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d').format(end)}";
  }
}

class _PlannerTimeline extends StatelessWidget {
  final DateTime baseDate;
  final int dayCount;
  final List<AvailabilityWindow> windows;
  final List<Map<String, dynamic>> personalEvents;
  final Function(AvailabilityWindow) onWindowTap;

  static const double hourHeight = 80.0;
  static const int startHour = 6;
  static const int endHour = 23;

  const _PlannerTimeline({
    required this.baseDate,
    required this.dayCount,
    required this.windows,
    required this.personalEvents,
    required this.onWindowTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.places;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate
            .normal, // We can't set 0.15 directly but normal is decent
      ),
      child: Container(
        padding: const EdgeInsets.only(top: 16, bottom: 32),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTimeLabels(theme),
            ...List.generate(dayCount, (index) {
              final date = baseDate.add(Duration(days: index));
              return Expanded(
                child: _DayColumn(
                  date: date,
                  windows: windows
                      .where((w) => DateUtils.isSameDay(w.date, date))
                      .toList(),
                  personalEvents: personalEvents.where((e) {
                    final start = e['startTime'] as DateTime;
                    return DateUtils.isSameDay(start, date);
                  }).toList(),
                  onWindowTap: onWindowTap,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeLabels(PlacesTheme theme) {
    return Container(
      width: 50,
      padding: const EdgeInsets.only(top: 40), // Align with day headers
      child: Column(
        children: List.generate(endHour - startHour + 1, (index) {
          final hour = startHour + index;
          final time = tz.TZDateTime(tz.local, 2024, 1, 1, hour);
          return SizedBox(
            height: hourHeight,
            child: Text(
              DateFormat('h a').format(time),
              style: PlacesType.label(theme.inkMuted).copyWith(fontSize: 10),
            ),
          );
        }),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  final DateTime date;
  final List<AvailabilityWindow> windows;
  final List<Map<String, dynamic>> personalEvents;
  final Function(AvailabilityWindow) onWindowTap;

  const _DayColumn({
    required this.date,
    required this.windows,
    required this.personalEvents,
    required this.onWindowTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final isToday = DateUtils.isSameDay(date, tz.TZDateTime.now(tz.local));

    return Column(
      children: [
        _buildDayHeader(theme, isToday),
        Container(
          height: (17 * _PlannerTimeline.hourHeight), // 6 AM to 11 PM
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: theme.ashSoft, width: 0.5)),
          ),
          child: Stack(
            children: [
              _buildHourLines(theme),
              ...windows.map((w) => _buildWindowTile(context, theme, w)),
              ...personalEvents.map((e) => _buildEventTile(theme, e)),
              if (isToday) _buildNowIndicator(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayHeader(PlacesTheme theme, bool isToday) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            DateFormat('EEE').format(date).toUpperCase(),
            style: PlacesType.label(isToday ? theme.anchor : theme.inkMuted)
                .copyWith(
                  fontSize: 10,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                ),
          ),
          Text(
            '${date.day}',
            style: PlacesType.title(
              isToday ? theme.anchor : theme.ink,
            ).copyWith(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildHourLines(PlacesTheme theme) {
    return Column(
      children: List.generate(17, (index) {
        return Container(
          height: _PlannerTimeline.hourHeight,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.ashSoft, width: 0.5),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildWindowTile(
    BuildContext context,
    PlacesTheme theme,
    AvailabilityWindow window,
  ) {
    final top = _getTopOffset(window.startTime);
    final height = _getHeight(window.startTime, window.endTime);

    return Positioned(
      top: top,
      left: 4,
      right: 4,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: theme.anchor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(PlacesRadius.md),
          border: Border.all(
            color: theme.anchor.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onWindowTap(window),
            borderRadius: BorderRadius.circular(PlacesRadius.md),
            splashColor: theme.anchor.withValues(alpha: 0.2),
            highlightColor: theme.anchor.withValues(alpha: 0.1),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.door_front_door_outlined,
                        size: 14,
                        color: theme.anchor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${window.placeCount} places open',
                        style: PlacesType.label(
                          theme.anchor,
                        ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  if (height > 40) ...[
                    const Spacer(),
                    Text(
                      'Open until ${DateFormat('h:mm a').format(window.endTime)}',
                      style: PlacesType.label(theme.ink).copyWith(fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventTile(PlacesTheme theme, Map<String, dynamic> event) {
    final start = event['startTime'] as DateTime;
    final end = event['endTime'] as DateTime;
    final top = _getTopOffset(start);
    final height = _getHeight(start, end);

    return Positioned(
      top: top,
      left: 4,
      right: 4,
      height: height,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.inkMuted.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(PlacesRadius.md),
          border: Border.all(
            color: theme.inkMuted.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Text(
          event['title'] as String,
          style: PlacesType.label(
            theme.ink,
          ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildNowIndicator(PlacesTheme theme) {
    final now = tz.TZDateTime.now(tz.local);
    if (now.hour < _PlannerTimeline.startHour ||
        now.hour > _PlannerTimeline.endHour)
      return const SizedBox.shrink();

    return Positioned(
      top: _getTopOffset(now),
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: theme.anchor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: Divider(color: theme.anchor, thickness: 2)),
        ],
      ),
    );
  }

  double _getTopOffset(DateTime time) {
    final minutes = (time.hour - _PlannerTimeline.startHour) * 60 + time.minute;
    return (minutes / 60.0) * _PlannerTimeline.hourHeight;
  }

  double _getHeight(DateTime start, DateTime end) {
    final durationMinutes = end.difference(start).inMinutes;
    return (durationMinutes / 60.0) * _PlannerTimeline.hourHeight;
  }
}
