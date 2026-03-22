import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';
import '../../models/saved_place.dart';
import '../../services/api_service.dart';
import '../../bloc/preferences/preferences_cubit.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

// ─── Calendar View Type ───────────────────────────────────────────
enum CalendarViewType { singleDay, threeDay, week }

// ─── Calendar Screen ──────────────────────────────────────────────
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarViewType _currentView = CalendarViewType.week;
  DateTime _baseDate = DateTime.now();

  // Saved places state
  List<SavedPlace> _savedPlaces = [];
  bool _isLoadingPlaces = true;
  final Set<String> _checkedPlaceIds = {};

  // Predefined palette for places without a custom color
  static const List<Color> _defaultPalette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.brown,
    Colors.indigo,
    Colors.cyan,
  ];

  static const Map<String, IconData> _availableIcons = {
    'restaurant': Icons.restaurant,
    'local_cafe': Icons.local_cafe,
    'local_bar': Icons.local_bar,
    'store': Icons.store,
    'shopping_cart': Icons.shopping_cart,
    'fitness_center': Icons.fitness_center,
    'local_hospital': Icons.local_hospital,
    'park': Icons.park,
    'star': Icons.star,
    'home': Icons.home,
    'work': Icons.work,
  };

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
  }

  Future<void> _loadSavedPlaces() async {
    try {
      final apiService = context.read<ApiService>();
      final bookmarks = await apiService.getBookmarks();
      if (mounted) {
        setState(() {
          _savedPlaces = bookmarks;
          _isLoadingPlaces = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPlaces = false);
      }
    }
  }

  // ── Color helper ──────────────────────────────────────────────
  Color _colorForPlace(SavedPlace sp, int index) {
    if (sp.color != null && sp.color!.isNotEmpty) {
      try {
        return Color(int.parse(sp.color!, radix: 16));
      } catch (_) {}
    }
    return _defaultPalette[index % _defaultPalette.length];
  }

  // ── Displayed name ────────────────────────────────────────────
  String _displayName(SavedPlace sp) {
    if (sp.customName != null && sp.customName!.isNotEmpty) return sp.customName!;
    return sp.place.name;
  }

  // ── Build the event controller with all checked places ────────
  EventController<Object?> _buildEventController() {
    final controller = EventController<Object?>();
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    int colorIndex = 0;
    for (final sp in _savedPlaces) {
      if (!_checkedPlaceIds.contains(sp.place.tomtomId)) {
        colorIndex++;
        continue;
      }

      final color = _colorForPlace(sp, colorIndex).withValues(alpha: 0.7);
      final label = _displayName(sp);

      for (int weekOffset = -4; weekOffset <= 12; weekOffset++) {
        final weekStart = startOfWeek.add(Duration(days: weekOffset * 7));

        for (final hours in sp.place.hours) {
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

          controller.add(CalendarEventData(
            title: label,
            date: baseDate,
            startTime: startTime,
            endTime: endTime,
            color: color,
          ));
        }
      }
      colorIndex++;
    }

    return controller;
  }

  // ── Event tile builder ────────────────────────────────────────
  Widget _buildEventTile(
    DateTime date,
    List<CalendarEventData<dynamic>> events,
    Rect boundary,
    DateTime startDuration,
    DateTime endDuration,
  ) {
    if (events.isEmpty) return const SizedBox.shrink();
    final event = events[0];

    return Container(
      decoration: BoxDecoration(
        color: event.color,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(4),
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
    );
  }

  // ── Weekday short name ────────────────────────────────────────
  String _weekDayShortName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }

  // ── Time line label ───────────────────────────────────────────
  Widget _buildTimeLineLabel(DateTime date, bool use24HourFormat, Color labelColor) {
    final timeString = use24HourFormat
        ? "${date.hour.toString().padLeft(2, '0')}:00"
        : DateFormat('h a').format(DateTime(date.year, date.month, date.day, date.hour));
    final label = Center(
      child: Text(timeString, style: TextStyle(color: labelColor, fontSize: 12)),
    );

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
            child: Center(
              child: Text(midnightString, style: TextStyle(color: labelColor, fontSize: 12)),
            ),
          ),
        ],
      );
    }
    return label;
  }

  // ── Calendar options (segmented button) ───────────────────────
  Widget _buildCalendarOptions() {
    return SegmentedButton<CalendarViewType>(
      segments: const [
        ButtonSegment(value: CalendarViewType.singleDay, label: Text('1 Day')),
        ButtonSegment(value: CalendarViewType.threeDay, label: Text('3 Days')),
        ButtonSegment(value: CalendarViewType.week, label: Text('Week')),
      ],
      selected: <CalendarViewType>{_currentView},
      onSelectionChanged: (Set<CalendarViewType> selection) {
        setState(() {
          _currentView = selection.first;
          _baseDate = DateTime.now();
        });
      },
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  // ── Calendar widget ───────────────────────────────────────────
  Widget _buildCalendar(Color textColor, Color textSmallColor, bool use24HourFormat) {
    List<WeekDays> weekDays = WeekDays.values;
    String headerText = "";
    int daysToAdvance = 0;
    bool showNavigation = true;

    if (_currentView == CalendarViewType.threeDay) {
      daysToAdvance = 3;
      weekDays = [
        WeekDays.values[_baseDate.weekday - 1],
        WeekDays.values[_baseDate.add(const Duration(days: 1)).weekday - 1],
        WeekDays.values[_baseDate.add(const Duration(days: 2)).weekday - 1],
      ];
      headerText = "3-Day Schedule";
    } else if (_currentView == CalendarViewType.singleDay) {
      daysToAdvance = 1;
      headerText = "Daily Schedule";
    } else {
      daysToAdvance = 7;
      headerText = "Weekly Schedule";
      showNavigation = false;
    }

    final now = DateTime.now();
    final initialScrollOffset = (now.hour * 60.0 + now.minute) * 1.0;

    Widget calendarWidget;
    if (_currentView == CalendarViewType.singleDay) {
      calendarWidget = DayView(
        key: ValueKey('day_${_baseDate}_${_checkedPlaceIds.length}'),
        controller: _buildEventController(),
        initialDay: _baseDate,
        scrollOffset: initialScrollOffset,
        minDay: _baseDate.subtract(const Duration(days: 28)),
        maxDay: _baseDate.add(const Duration(days: 84)),
        heightPerMinute: 1,
        scrollPhysics: const ClampingScrollPhysics(),
        pageViewPhysics: const NeverScrollableScrollPhysics(),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        headerStyle: HeaderStyle(
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        eventArranger: const _StackEventArranger(),
        eventTileBuilder: _buildEventTile,
        showLiveTimeLineInAllDays: true,
        dayTitleBuilder: (date) => const SizedBox.shrink(),
        hourIndicatorSettings: HourIndicatorSettings(color: Theme.of(context).dividerColor),
        liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
          color: Theme.of(context).colorScheme.primary,
        ),
        timeLineBuilder: (date) => _buildTimeLineLabel(
          date,
          use24HourFormat,
          Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
        ),
      );
    } else {
      calendarWidget = WeekView(
        key: ValueKey('week_${_baseDate}_${_currentView}_${_checkedPlaceIds.length}'),
        controller: _buildEventController(),
        minDay: _baseDate.subtract(const Duration(days: 28)),
        maxDay: _baseDate.add(const Duration(days: 84)),
        initialDay: _baseDate,
        scrollOffset: initialScrollOffset,
        startDay: _currentView == CalendarViewType.threeDay
            ? WeekDays.values[_baseDate.weekday - 1]
            : WeekDays.monday,
        weekDays: weekDays,
        heightPerMinute: 1,
        scrollPhysics: const ClampingScrollPhysics(),
        pageViewPhysics: const NeverScrollableScrollPhysics(),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        headerStyle: HeaderStyle(
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        weekTitleBackgroundColor: const Color(0xFF1565C0),
        eventArranger: const _StackEventArranger(),
        eventTileBuilder: _buildEventTile,
        showLiveTimeLineInAllDays: true,
        weekPageHeaderBuilder: (start, end) => const SizedBox.shrink(),
        weekNumberBuilder: (date) => const SizedBox.shrink(),
        hourIndicatorSettings: HourIndicatorSettings(color: Theme.of(context).dividerColor),
        liveTimeIndicatorSettings: LiveTimeIndicatorSettings(
          color: Theme.of(context).colorScheme.primary,
          showBullet: false,
        ),
        timeLineBuilder: (date) => _buildTimeLineLabel(
          date,
          use24HourFormat,
          Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
        ),
        weekDayBuilder: (date) {
          final isToday = DateUtils.isSameDay(date, DateTime.now());
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: isToday
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                    )
                  : null,
              child: Text(
                _weekDayShortName(date.weekday),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _baseDate = _baseDate.subtract(Duration(days: daysToAdvance));
                    });
                  },
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Text(
                  headerText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _baseDate = _baseDate.add(Duration(days: daysToAdvance));
                    });
                  },
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    secondaryContainer: Theme.of(context).scaffoldBackgroundColor,
                    primaryContainer: Theme.of(context).scaffoldBackgroundColor,
                    surface: Theme.of(context).scaffoldBackgroundColor,
                    error: Colors.transparent,
                  ),
              canvasColor: Theme.of(context).scaffoldBackgroundColor,
              cardColor: Theme.of(context).scaffoldBackgroundColor,
              secondaryHeaderColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: calendarWidget,
          ),
        ),
      ],
    );
  }

  // ── Saved places sidebar ──────────────────────────────────────
  Widget _buildPlacesSidebar() {
    if (_isLoadingPlaces) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_savedPlaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'No saved places yet',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Save places from Search to see their hours here',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _savedPlaces.length,
      itemBuilder: (context, index) {
        final sp = _savedPlaces[index];
        final isChecked = _checkedPlaceIds.contains(sp.place.tomtomId);
        final color = _colorForPlace(sp, index);
        final iconName = sp.icon ?? 'star';
        final iconData = _availableIcons[iconName] ?? Icons.star;

        return CheckboxListTile(
          value: isChecked,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _checkedPlaceIds.add(sp.place.tomtomId);
              } else {
                _checkedPlaceIds.remove(sp.place.tomtomId);
              }
            });
          },
          secondary: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, color: Colors.white, size: 20),
          ),
          title: Text(
            _displayName(sp),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: sp.place.hours.isNotEmpty
              ? Text(
                  '${sp.place.hours.length} schedule${sp.place.hours.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : Text(
                  'No hours available',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: color,
        );
      },
    );
  }

  // ── Main build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final textSmallColor = isDark ? Colors.white70 : Colors.black87;
    final use24HourFormat = context.watch<PreferencesCubit>().state.use24HourFormat;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Calendar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _buildCalendarOptions(),
          ),
        ],
      ),
      body: Row(
        children: [
          // ── Calendar view (left 2/3) ──
          Expanded(
            flex: 2,
            child: _buildCalendar(textColor, textSmallColor, use24HourFormat),
          ),
          const VerticalDivider(width: 1),
          // ── Saved places sidebar (right 1/3) ──
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'My Places',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      if (_checkedPlaceIds.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _checkedPlaceIds.clear()),
                          child: const Text('Clear All'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: () {
                          setState(() => _isLoadingPlaces = true);
                          _loadSavedPlaces();
                        },
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(child: _buildPlacesSidebar()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stack Event Arranger (reused from PlaceDetailScreen) ────────
class _StackEventArranger<T extends Object?> extends EventArranger<T> {
  const _StackEventArranger();

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

      arrangedEvents.add(OrganizedCalendarEventData<T>(
        calendarViewDate: calendarViewDate,
        startDuration: startTime,
        endDuration: endTime,
        top: top,
        bottom: bottom,
        left: 0.0,
        right: 0.0,
        events: [event],
      ));
    }

    return arrangedEvents;
  }
}
