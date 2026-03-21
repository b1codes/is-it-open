import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';
import '../../models/place.dart';
import '../../services/api_service.dart';

class PlaceDetailScreen extends StatefulWidget {
  final Place place;

  const PlaceDetailScreen({super.key, required this.place});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

enum CalendarViewType {
  singleDay,
  threeDay,
  week,
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  CalendarViewType _currentView = CalendarViewType.week;
  DateTime _baseDate = DateTime.now();

  String _weekDayShortName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }

  EventController<Object?> _buildEventController() {
    final controller = EventController<Object?>();
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    // Generate events for 4 weeks in the past and 12 weeks in the future
    for (int weekOffset = -4; weekOffset <= 12; weekOffset++) {
      final weekStart = startOfWeek.add(Duration(days: weekOffset * 7));
      
      for (final hours in widget.place.hours) {
        final baseDate = weekStart.add(Duration(days: hours.dayOfWeek));
        final startTime = DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
          hours.openTime.hour,
          hours.openTime.minute,
        );

        var endTime = DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
          hours.closeTime.hour,
          hours.closeTime.minute,
        );

        if (endTime.isBefore(startTime)) {
          endTime = endTime.add(const Duration(days: 1));
        }

        controller.add(
          CalendarEventData(
            title: 'Open',
            date: baseDate,
            startTime: startTime,
            endTime: endTime,
            color: Colors.green.withValues(alpha: 0.7),
          ),
        );
      }
    }

    return controller;
  }

  Widget _buildCalendarOptions() {
    return SegmentedButton<CalendarViewType>(
      segments: const [
        ButtonSegment(
          value: CalendarViewType.singleDay,
          label: Text('1 Day'),
        ),
        ButtonSegment(
          value: CalendarViewType.threeDay,
          label: Text('3 Days'),
        ),
        ButtonSegment(
          value: CalendarViewType.week,
          label: Text('Week'),
        ),
      ],
      selected: <CalendarViewType>{_currentView},
      onSelectionChanged: (Set<CalendarViewType> selection) {
        setState(() {
          _currentView = selection.first;
          _baseDate = DateTime.now();
        });
      },
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildCalendar(Color textColor, Color textSmallColor) {
    List<WeekDays> weekDays = WeekDays.values;
    int daysToAdvance = 7;
    String headerText = "";

    if (_currentView == CalendarViewType.threeDay) {
      daysToAdvance = 3;
      weekDays = [
        WeekDays.values[_baseDate.weekday - 1],
        WeekDays.values[_baseDate.add(const Duration(days: 1)).weekday - 1],
        WeekDays.values[_baseDate.add(const Duration(days: 2)).weekday - 1],
      ];
      final endDate = _baseDate.add(const Duration(days: 2));
      headerText = "${_baseDate.month}/${_baseDate.day} - ${endDate.month}/${endDate.day}";
    } else if (_currentView == CalendarViewType.singleDay) {
      daysToAdvance = 1;
      headerText = "${_baseDate.month}/${_baseDate.day}/${_baseDate.year}";
    } else {
      daysToAdvance = 7;
      final start = _baseDate.subtract(Duration(days: _baseDate.weekday - 1));
      final end = start.add(const Duration(days: 6));
      headerText = "${start.month}/${start.day} - ${end.month}/${end.day}";
    }

    Widget calendarWidget;
    if (_currentView == CalendarViewType.singleDay) {
      calendarWidget = DayView(
        key: ValueKey(_baseDate),
        controller: _buildEventController(),
        initialDay: _baseDate,
        minDay: _baseDate.subtract(const Duration(days: 28)),
        maxDay: _baseDate.add(const Duration(days: 84)),
        heightPerMinute: 1, // Compact view
        scrollPhysics: const ClampingScrollPhysics(),
        pageViewPhysics: const NeverScrollableScrollPhysics(),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        dayTitleBuilder: (date) => const SizedBox.shrink(),
        hourIndicatorSettings: HourIndicatorSettings(
          color: Theme.of(context).dividerColor,
        ),
        liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
          color: Theme.of(context).colorScheme.primary,
        ),
        timeLineBuilder: (date) => Center(
          child: Text(
            "${date.hour.toString().padLeft(2, '0')}:00",
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
              fontSize: 12,
            ),
          ),
        ),
      );
    } else {
      calendarWidget = WeekView(
        key: ValueKey(_baseDate),
        controller: _buildEventController(),
        minDay: _baseDate.subtract(const Duration(days: 28)),
        maxDay: _baseDate.add(const Duration(days: 84)),
        initialDay: _baseDate,
        startDay: _currentView == CalendarViewType.threeDay
            ? WeekDays.values[_baseDate.weekday - 1]
            : WeekDays.monday,
        weekDays: weekDays,
        heightPerMinute: 1, // Compact view
        scrollPhysics: const ClampingScrollPhysics(),
        pageViewPhysics: const NeverScrollableScrollPhysics(),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        weekPageHeaderBuilder: (start, end) => const SizedBox.shrink(),
        hourIndicatorSettings: HourIndicatorSettings(
          color: Theme.of(context).dividerColor,
        ),
        liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
          color: Theme.of(context).colorScheme.primary,
        ),
        timeLineBuilder: (date) => Center(
          child: Text(
            "${date.hour.toString().padLeft(2, '0')}:00",
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
              fontSize: 12,
            ),
          ),
        ),
        weekDayBuilder: (date) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _weekDayShortName(date.weekday),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
                  fontSize: 12,
                ),
              ),
              Text(
                date.day.toString(),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color ?? textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _baseDate = _baseDate.subtract(Duration(days: daysToAdvance));
                  });
                },
              ),
              Expanded(
                child: Text(
                  headerText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _baseDate = _baseDate.add(Duration(days: daysToAdvance));
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: calendarWidget,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final textSmallColor = isDark ? Colors.white70 : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.place.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              try {
                final apiService = context.read<ApiService>();
                await apiService.deleteBookmark(widget.place.tomtomId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Removed from My Places'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error deleting place'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.place.address,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  // More details will be added here later
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                  child: _buildCalendarOptions(),
                ),
                Expanded(
                  child: _buildCalendar(textColor, textSmallColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
