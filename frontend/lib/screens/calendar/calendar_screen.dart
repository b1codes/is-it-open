import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:convert' show utf8, jsonEncode, jsonDecode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/saved_place.dart';
import '../../services/api_service.dart';
import '../../bloc/preferences/preferences_cubit.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../models/user.dart';
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

  // Device calendars state
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();
  List<Calendar> _deviceCalendars = [];
  List<CalendarEventData<Object?>> _deviceEvents = [];
  final Set<String> _checkedCalendarIds = {};
  bool _isLoadingCalendars = false;
  bool _hasCalendarPermission = false;
  bool _permissionRequestedOnce = false;

  // Imported events (iCal/ICS)
  List<CalendarEventData<Object?>> _importedEvents = [];
  bool _isImporting = false;

  // Remote subscription state
  List<CalendarEventData<Object?>> _remoteEvents = [];
  bool _isLoadingRemote = false;

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
    _initDeviceCalendar();
    _loadPersistedImportedEvents();
    _fetchRemoteCalendar();
  }

  Future<void> _loadPersistedImportedEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? eventsJson = prefs.getString('persisted_imported_events');
      if (eventsJson != null) {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        final List<CalendarEventData<Object?>> events = decoded.map((e) {
          return CalendarEventData(
            title: e['title'],
            date: DateTime.parse(e['date']),
            startTime: DateTime.parse(e['startTime']),
            endTime: DateTime.parse(e['endTime']),
            description: e['description'],
            color: Colors.teal.withOpacity(0.5),
          );
        }).toList();
        if (mounted) {
          setState(() => _importedEvents = events);
        }
      }
    } catch (e) {
      debugPrint('Error loading persisted events: $e');
    }
  }

  Future<void> _persistImportedEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> toStore = _importedEvents.map((e) {
        return {
          'title': e.title,
          'date': e.date.toIso8601String(),
          'startTime': e.startTime?.toIso8601String(),
          'endTime': e.endTime?.toIso8601String(),
          'description': e.description,
        };
      }).toList();
      await prefs.setString('persisted_imported_events', jsonEncode(toStore));
    } catch (e) {
      debugPrint('Error persisting events: $e');
    }
  }

  /// Returns true if the IcsDateTime represents a date-only value (all-day).
  bool _isAllDayIcsDateTime(IcsDateTime dt) {
    // Date-only values in iCal have no 'T' separator and are 8 chars (YYYYMMDD)
    return !dt.dt.contains('T');
  }

  Future<void> _fetchRemoteCalendar() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final url = authState.user.calendarSubscriptionUrl;
    if (url == null || url.isEmpty) return;

    setState(() => _isLoadingRemote = true);
    try {
      final apiService = context.read<ApiService>();
      final icsString = await apiService.getCalendarFromUrl(url);
      final iCalendar = ICalendar.fromString(icsString);
      
      final List<CalendarEventData<Object?>> events = [];
      for (final entry in iCalendar.data) {
        if (entry['type'] == 'VEVENT') {
          final title = entry['summary'] ?? 'Remote Event';
          final dtstart = entry['dtstart'] as IcsDateTime?;
          final dtend = entry['dtend'] as IcsDateTime?;
          final description = entry['description'];

          if (dtstart != null) {
            final isAllDay = _isAllDayIcsDateTime(dtstart);
            final start = dtstart.toDateTime();
            final end = dtend?.toDateTime() ?? start?.add(const Duration(hours: 1));
            
            if (start != null) {
              if (isAllDay) {
                // All-day event: omit startTime/endTime for header display
                final endDate = end != null
                    ? end.subtract(const Duration(days: 1))
                    : start;
                events.add(CalendarEventData(
                  title: title,
                  date: start,
                  endDate: endDate,
                  description: description,
                  color: Colors.deepPurple.withOpacity(0.5),
                ));
              } else {
                events.add(CalendarEventData(
                  title: title,
                  date: start,
                  startTime: start,
                  endTime: end ?? start,
                  description: description,
                  color: Colors.deepPurple.withOpacity(0.5),
                ));
              }
            }
          }
        }
      }
      if (mounted) {
        setState(() => _remoteEvents = events);
      }
    } catch (e) {
      debugPrint('Error fetching remote calendar: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingRemote = false);
      }
    }
  }

  Future<void> _updateSubscriptionUrl(String url) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    
    final updatedUser = User(
      id: authState.user.id,
      username: authState.user.username,
      calendarSubscriptionUrl: url,
    );
    
    context.read<AuthBloc>().add(ProfileUpdateRequested(updatedUser: updatedUser));
  }

  Future<void> _initDeviceCalendar({bool fromButton = false}) async {
    // Only support mobile for local device calendar sync for now
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    setState(() => _isLoadingCalendars = true);
    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && (permissionsGranted.data == false)) {
        permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      }

      if (permissionsGranted.isSuccess && permissionsGranted.data == true) {
        if (mounted) {
          setState(() => _hasCalendarPermission = true);
        }
        await _loadDeviceCalendars();
      } else if (fromButton && mounted) {
        // Permission was denied — if we already asked once, the OS won't
        // show the dialog again. Guide the user to Settings.
        if (_permissionRequestedOnce) {
          _showPermissionDeniedDialog();
        }
      }
      _permissionRequestedOnce = true;
    } catch (e) {
      debugPrint('Error initializing device calendar: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingCalendars = false);
      }
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Calendar Permission Required'),
        content: const Text(
          'Calendar permission was not granted. '
          'Please open Settings > Is It Open? and enable Calendars access, then try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDeviceCalendars() async {
    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    if (calendarsResult.isSuccess && calendarsResult.data != null) {
      if (mounted) {
        setState(() {
          _deviceCalendars = calendarsResult.data!;
        });
      }
    }
  }

  Future<void> _loadDeviceEvents() async {
    if (_checkedCalendarIds.isEmpty) {
      setState(() => _deviceEvents = []);
      return;
    }

    // Build a lookup map for calendar colors
    final calendarColorMap = <String, Color>{};
    for (final cal in _deviceCalendars) {
      if (cal.id != null) {
        calendarColorMap[cal.id!] = cal.color != null
            ? Color(cal.color!).withOpacity(0.7)
            : Colors.blue.withOpacity(0.7);
      }
    }

    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 28));
    final endDate = now.add(const Duration(days: 84));

    List<CalendarEventData<Object?>> allEvents = [];

    for (final calendarId in _checkedCalendarIds) {
      final calColor = calendarColorMap[calendarId] ?? Colors.blue.withOpacity(0.7);

      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(startDate: startDate, endDate: endDate),
      );

      if (eventsResult.isSuccess && eventsResult.data != null) {
        for (final event in eventsResult.data!) {
          if (event.start != null && event.end != null) {
            if (event.allDay == true) {
              // Full-day event: omit startTime/endTime so calendar_view
              // treats it as a full-day event shown in the header area.
              allEvents.add(CalendarEventData(
                title: event.title ?? 'No Title',
                date: event.start!,
                endDate: event.end!.subtract(const Duration(days: 1)),
                description: event.description,
                color: calColor,
              ));
            } else {
              allEvents.add(CalendarEventData(
                title: event.title ?? 'No Title',
                date: event.start!,
                startTime: event.start!,
                endTime: event.end!,
                description: event.description,
                color: calColor,
              ));
            }
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _deviceEvents = allEvents;
      });
    }
  }

  Future<void> _importIcalFile() async {
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ics'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final icsString = utf8.decode(result.files.single.bytes!);
        final iCalendar = ICalendar.fromString(icsString);
        
        final List<CalendarEventData<Object?>> events = [];
        for (final entry in iCalendar.data) {
          if (entry['type'] == 'VEVENT') {
            final title = entry['summary'] ?? 'Imported Event';
            final dtstart = entry['dtstart'] as IcsDateTime?;
            final dtend = entry['dtend'] as IcsDateTime?;
            final description = entry['description'];

            if (dtstart != null) {
              final isAllDay = _isAllDayIcsDateTime(dtstart);
              final start = dtstart.toDateTime();
              final end = dtend?.toDateTime() ?? start?.add(const Duration(hours: 1));
              
              if (start != null) {
                if (isAllDay) {
                  final endDate = end != null
                      ? end.subtract(const Duration(days: 1))
                      : start;
                  events.add(CalendarEventData(
                    title: title,
                    date: start,
                    endDate: endDate,
                    description: description,
                    color: Colors.teal.withOpacity(0.5),
                  ));
                } else {
                  events.add(CalendarEventData(
                    title: title,
                    date: start,
                    startTime: start,
                    endTime: end ?? start,
                    description: description,
                    color: Colors.teal.withOpacity(0.5),
                  ));
                }
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _importedEvents = events;
            _persistImportedEvents();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imported ${events.length} events successfully!')),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing iCal: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
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

      final color = _colorForPlace(sp, colorIndex).withOpacity(0.7);
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

    // Add device events
    for (final event in _deviceEvents) {
      controller.add(event);
    }

    // Add imported events
    for (final event in _importedEvents) {
      controller.add(event);
    }

    // Add remote events
    for (final event in _remoteEvents) {
      controller.add(event);
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
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  // ── Full-day event header builder ─────────────────────────────
  Widget _buildFullDayEventWidget(
    List<CalendarEventData<dynamic>> events,
    DateTime date,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: events.map((event) {
          return Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: event.color,
              borderRadius: BorderRadius.circular(4),
            ),
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
        }).toList(),
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

  // ── Date formatting helpers ────────────────────────────────────
  String _formatHeaderDate(DateTime date) {
    return DateFormat('MMM d').format(date);
  }

  String _buildHeaderText() {
    if (_currentView == CalendarViewType.singleDay) {
      return DateFormat('EEEE, MMM d, yyyy').format(_baseDate);
    } else if (_currentView == CalendarViewType.threeDay) {
      final endDate = _baseDate.add(const Duration(days: 2));
      if (_baseDate.month == endDate.month) {
        return '${_formatHeaderDate(_baseDate)} – ${endDate.day}, ${DateFormat('yyyy').format(endDate)}';
      }
      return '${_formatHeaderDate(_baseDate)} – ${_formatHeaderDate(endDate)}, ${DateFormat('yyyy').format(endDate)}';
    } else {
      // Week view: show Mon – Sun range
      final weekStart = _baseDate.subtract(Duration(days: _baseDate.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      if (weekStart.month == weekEnd.month) {
        return '${_formatHeaderDate(weekStart)} – ${weekEnd.day}, ${DateFormat('yyyy').format(weekEnd)}';
      }
      return '${_formatHeaderDate(weekStart)} – ${_formatHeaderDate(weekEnd)}, ${DateFormat('yyyy').format(weekEnd)}';
    }
  }

  // ── Calendar widget ───────────────────────────────────────────
  Widget _buildCalendar(Color textColor, Color textSmallColor, bool use24HourFormat) {
    List<WeekDays> weekDays = WeekDays.values;
    int daysToAdvance = 0;

    if (_currentView == CalendarViewType.threeDay) {
      daysToAdvance = 3;
      weekDays = [
        WeekDays.values[_baseDate.weekday - 1],
        WeekDays.values[_baseDate.add(const Duration(days: 1)).weekday - 1],
        WeekDays.values[_baseDate.add(const Duration(days: 2)).weekday - 1],
      ];
    } else if (_currentView == CalendarViewType.singleDay) {
      daysToAdvance = 1;
    } else {
      daysToAdvance = 7;
    }

    final now = DateTime.now();
    final initialScrollOffset = (now.hour * 60.0 + now.minute) * 1.0;
    final isShowingToday = DateUtils.isSameDay(_baseDate, now) ||
        (_currentView == CalendarViewType.week &&
            _baseDate.subtract(Duration(days: _baseDate.weekday - 1)).isBefore(now) &&
            _baseDate.subtract(Duration(days: _baseDate.weekday - 1)).add(const Duration(days: 7)).isAfter(now));

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
        fullDayEventBuilder: _buildFullDayEventWidget,
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
        fullDayEventBuilder: _buildFullDayEventWidget,
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
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.4)),
                    )
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _weekDayShortName(date.weekday),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${date.month}/${date.day}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
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
                  _buildHeaderText(),
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
              if (!isShowingToday)
                TextButton.icon(
                  onPressed: () => setState(() => _baseDate = DateTime.now()),
                  icon: const Icon(Icons.today, size: 18),
                  label: const Text('Today'),
                ),
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
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: color,
        );
      },
    );
  }

  Widget _buildDeviceCalendarsSidebar() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(Icons.devices_other, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
            const SizedBox(height: 8),
            Text(
              'Device sync is available on Mobile only. For Web/Desktop, consider cloud sync (coming soon).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (!_hasCalendarPermission) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Grant permission to see your device calendars.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _initDeviceCalendar(fromButton: true),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (_isLoadingCalendars) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }

    if (_deviceCalendars.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No calendars found on this device.', textAlign: TextAlign.center),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _deviceCalendars.length,
      itemBuilder: (context, index) {
        final cal = _deviceCalendars[index];
        final isChecked = _checkedCalendarIds.contains(cal.id);
        final color = cal.color != null ? Color(cal.color!) : Colors.blue;

        return CheckboxListTile(
          value: isChecked,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _checkedCalendarIds.add(cal.id!);
              } else {
                _checkedCalendarIds.remove(cal.id);
              }
            });
            _loadDeviceEvents();
          },
          secondary: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            cal.name ?? 'Unnamed Calendar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
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
    final isMobile = MediaQuery.of(context).size.width < 800;

    Widget sidebarContent = ListView(
      children: [
        // Section: My Places
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                'My Places',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () {
                  setState(() => _isLoadingPlaces = true);
                  _loadSavedPlaces();
                },
              ),
            ],
          ),
        ),
        _buildPlacesSidebar(),
        const Divider(),
        // Section: Device Calendars
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                'Device Calendars',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_hasCalendarPermission)
                IconButton(
                  icon: const Icon(Icons.sync, size: 18),
                  onPressed: _loadDeviceCalendars,
                ),
            ],
          ),
        ),
        _buildDeviceCalendarsSidebar(),
        const Divider(),
        // Section: Remote Subscription
        _buildRemoteSubscriptionSidebar(),
        const Divider(),
        // Section: Imported Calendars
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                'Imported Events',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_importedEvents.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => setState(() {
                    _importedEvents = [];
                    _persistImportedEvents();
                  }),
                  tooltip: 'Clear Imported',
                ),
              IconButton(
                icon: _isImporting 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_upload, size: 18),
                onPressed: _isImporting ? null : _importIcalFile,
                tooltip: 'Import .ics file',
              ),
            ],
          ),
        ),
        if (_importedEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No events imported. Upload a .ics file to see external events.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Displaying ${_importedEvents.length} imported events.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _buildCalendarOptions(),
          ),
          if (isMobile)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
        ],
      ),
      endDrawer: isMobile ? Drawer(child: sidebarContent) : null,
      body: isMobile
          ? _buildCalendar(textColor, textSmallColor, use24HourFormat)
          : Row(
              children: [
                // ── Calendar view (left 2/3) ──
                Expanded(
                  flex: 2,
                  child: _buildCalendar(textColor, textSmallColor, use24HourFormat),
                ),
                const VerticalDivider(width: 1),
                // ── Sidebar (right 1/3) ──
                Expanded(
                  flex: 1,
                  child: sidebarContent,
                ),
              ],
            ),
    );
  }

  Widget _buildRemoteSubscriptionSidebar() {
    final authState = context.watch<AuthBloc>().state;
    final url = authState is AuthAuthenticated ? authState.user.calendarSubscriptionUrl : null;
    final hasUrl = url != null && url.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                'Remote Sync',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (hasUrl)
                IconButton(
                  icon: _isLoadingRemote
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  onPressed: _isLoadingRemote ? null : _fetchRemoteCalendar,
                ),
              IconButton(
                icon: const Icon(Icons.settings, size: 18),
                onPressed: _showSubscriptionDialog,
              ),
            ],
          ),
        ),
        if (!hasUrl)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No subscription URL set. Use a .ics URL for real-time sync.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Text(
              'Syncing with ${_remoteEvents.length} events.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }

  void _showSubscriptionDialog() {
    final authState = context.read<AuthBloc>().state;
    final currentUrl = authState is AuthAuthenticated ? authState.user.calendarSubscriptionUrl : '';
    final controller = TextEditingController(text: currentUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Calendar Subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter a "Secret iCal URL" (ends in .ics) from iCloud, Outlook, or Proton.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'iCal URL',
                hintText: 'https://example.com/calendar.ics',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _updateSubscriptionUrl(controller.text);
              Navigator.pop(context);
              // Small delay to allow profile update to finish before fetching
              Future.delayed(const Duration(seconds: 1), _fetchRemoteCalendar);
            },
            child: const Text('Save & Sync'),
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
