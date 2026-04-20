import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:convert' show utf8;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';
import '../../components/calendar/calendar_event_tile.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/saved_place.dart';
import '../../services/api_service.dart';
import '../../bloc/preferences/preferences_cubit.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../models/user.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

import '../../bloc/calendar/calendar_ui_cubit.dart';
import '../../bloc/calendar/calendar_ui_state.dart';
import '../../bloc/calendar/calendar_data_bloc.dart';
import '../../bloc/calendar/calendar_data_event.dart';
import '../../bloc/calendar/calendar_data_state.dart';

// ─── Calendar Screen ──────────────────────────────────────────────
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<CalendarUiCubit>(
          create: (context) => CalendarUiCubit(),
        ),
        BlocProvider<CalendarDataBloc>(
          create: (context) {
            final bloc = CalendarDataBloc(apiService: context.read<ApiService>());
            bloc.add(LoadSavedPlaces());
            bloc.add(const InitDeviceCalendar());
            
            // Load remote events if authenticated
            final authState = context.read<AuthBloc>().state;
            if (authState is AuthAuthenticated) {
              final url = authState.user.calendarSubscriptionUrl;
              if (url != null && url.isNotEmpty) {
                bloc.add(LoadRemoteEvents(url));
              }
            }
            return bloc;
          },
        ),
      ],
      child: const _CalendarScreenView(),
    );
  }
}

class _CalendarScreenView extends StatelessWidget {
  const _CalendarScreenView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<CalendarDataBloc, CalendarDataState>(
      listenWhen: (previous, current) =>
          current.errorMessage != null && current.errorMessage != previous.errorMessage,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage!)),
          );
        }
      },
      child: const _CalendarScreenContent(),
    );
  }
}

class _CalendarScreenContent extends StatelessWidget {
  const _CalendarScreenContent();

  static const List<Color> _defaultPalette = [
    Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.brown, Colors.indigo, Colors.cyan,
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

  Color _colorForPlace(SavedPlace sp, int index) {
    if (sp.color != null && sp.color!.isNotEmpty) {
      try {
        return Color(int.parse(sp.color!, radix: 16));
      } catch (_) {}
    }
    return _defaultPalette[index % _defaultPalette.length];
  }

  String _displayName(SavedPlace sp) {
    if (sp.customName != null && sp.customName!.isNotEmpty) {
      return sp.customName!;
    }
    return sp.place.name;
  }

  EventController<Object?> _buildEventController(CalendarDataState dataState) {
    final controller = EventController<Object?>();
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    int colorIndex = 0;
    for (final sp in dataState.savedPlaces) {
      if (!dataState.checkedPlaceIds.contains(sp.place.tomtomId)) {
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
            baseDate.year, baseDate.month, baseDate.day,
            hours.openTime.hour, hours.openTime.minute,
          );
          var endTime = DateTime(
            baseDate.year, baseDate.month, baseDate.day,
            hours.closeTime.hour, hours.closeTime.minute,
          );
          if (endTime.isBefore(startTime)) {
            endTime = endTime.add(const Duration(days: 1));
          }

          controller.add(
            CalendarEventData(
              title: label,
              date: baseDate,
              startTime: startTime,
              endTime: endTime,
              color: color,
            ),
          );
        }
      }
      colorIndex++;
    }

    controller.addAll(dataState.deviceEvents);
    controller.addAll(dataState.importedEvents);
    controller.addAll(dataState.remoteEvents);

    return controller;
  }



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
        : DateFormat('h a').format(DateTime(date.year, date.month, date.day, date.hour));
    final label = Center(
      child: Text(
        timeString,
        style: TextStyle(color: labelColor, fontSize: 12),
      ),
    );

    if (date.hour == 1) {
      final midnightString = use24HourFormat ? '00:00' : '12 AM';
      return Stack(
        clipBehavior: Clip.none,
        children: [
          label,
          Positioned(
            top: -60, height: 60, left: 0, right: 0,
            child: Center(
              child: Text(
                midnightString,
                style: TextStyle(color: labelColor, fontSize: 12),
              ),
            ),
          ),
        ],
      );
    }
    return label;
  }

  Widget _buildCalendarOptions(BuildContext context, CalendarViewType currentView) {
    return SegmentedButton<CalendarViewType>(
      segments: const [
        ButtonSegment(value: CalendarViewType.singleDay, label: Text('1 Day')),
        ButtonSegment(value: CalendarViewType.threeDay, label: Text('3 Days')),
        ButtonSegment(value: CalendarViewType.week, label: Text('Week')),
      ],
      selected: <CalendarViewType>{currentView},
      onSelectionChanged: (Set<CalendarViewType> selection) {
        context.read<CalendarUiCubit>().changeViewType(selection.first);
      },
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  String _formatHeaderDate(DateTime date) {
    return DateFormat('MMM d').format(date);
  }

  String _buildHeaderText(CalendarViewType currentView, DateTime baseDate) {
    if (currentView == CalendarViewType.singleDay) {
      return DateFormat('EEEE, MMM d, yyyy').format(baseDate);
    } else if (currentView == CalendarViewType.threeDay) {
      final endDate = baseDate.add(const Duration(days: 2));
      if (baseDate.month == endDate.month) {
        return '${_formatHeaderDate(baseDate)} – ${endDate.day}, ${DateFormat('yyyy').format(endDate)}';
      }
      return '${_formatHeaderDate(baseDate)} – ${_formatHeaderDate(endDate)}, ${DateFormat('yyyy').format(endDate)}';
    } else {
      final weekStart = baseDate.subtract(Duration(days: baseDate.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      if (weekStart.month == weekEnd.month) {
        return '${_formatHeaderDate(weekStart)} – ${weekEnd.day}, ${DateFormat('yyyy').format(weekEnd)}';
      }
      return '${_formatHeaderDate(weekStart)} – ${_formatHeaderDate(weekEnd)}, ${DateFormat('yyyy').format(weekEnd)}';
    }
  }

  Widget _buildCalendar(BuildContext context, Color textColor, Color textSmallColor, bool use24HourFormat) {
    return BlocBuilder<CalendarUiCubit, CalendarUiState>(
      builder: (context, uiState) {
        return BlocBuilder<CalendarDataBloc, CalendarDataState>(
          builder: (context, dataState) {
            final controller = _buildEventController(dataState);

            List<WeekDays> weekDays = WeekDays.values;
            int daysToAdvance = 0;

            if (uiState.currentView == CalendarViewType.threeDay) {
              daysToAdvance = 3;
              weekDays = [
                WeekDays.values[uiState.baseDate.weekday - 1],
                WeekDays.values[uiState.baseDate.add(const Duration(days: 1)).weekday - 1],
                WeekDays.values[uiState.baseDate.add(const Duration(days: 2)).weekday - 1],
              ];
            } else if (uiState.currentView == CalendarViewType.singleDay) {
              daysToAdvance = 1;
            } else {
              daysToAdvance = 7;
            }

            final now = DateTime.now();
            final initialScrollOffset = (now.hour * 60.0 + now.minute) * 1.0;
            final isShowingToday = DateUtils.isSameDay(uiState.baseDate, now) ||
                (uiState.currentView == CalendarViewType.week &&
                    uiState.baseDate.subtract(Duration(days: uiState.baseDate.weekday - 1)).isBefore(now) &&
                    uiState.baseDate.subtract(Duration(days: uiState.baseDate.weekday - 1)).add(const Duration(days: 7)).isAfter(now));

            Widget calendarWidget;
            if (uiState.currentView == CalendarViewType.singleDay) {
              calendarWidget = DayView(
                key: ValueKey('day_${uiState.baseDate}_${dataState.checkedPlaceIds.length}'),
                controller: controller,
                initialDay: uiState.baseDate,
                scrollOffset: initialScrollOffset,
                minDay: uiState.baseDate.subtract(const Duration(days: 28)),
                maxDay: uiState.baseDate.add(const Duration(days: 84)),
                heightPerMinute: 1,
                scrollPhysics: const ClampingScrollPhysics(),
                pageViewPhysics: const NeverScrollableScrollPhysics(),
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                headerStyle: HeaderStyle(decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor)),
                eventArranger: const StackEventArranger(),
                eventTileBuilder: (date, events, boundary, startDuration, endDuration) =>
                    CalendarEventTileWidget(
                  date: date,
                  events: events,
                  boundary: boundary,
                  startDuration: startDuration,
                  endDuration: endDuration,
                ),
                fullDayEventBuilder: (events, date) =>
                    FullDayEventWidget(events: events, date: date),
                showLiveTimeLineInAllDays: true,
                dayTitleBuilder: (date) => const SizedBox.shrink(),
                hourIndicatorSettings: HourIndicatorSettings(color: Theme.of(context).dividerColor),
                liveTimeIndicatorSettings: LiveTimeIndicatorSettings(color: Theme.of(context).colorScheme.primary),
                timeLineBuilder: (date) => _buildTimeLineLabel(
                  date, use24HourFormat, Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
                ),
              );
            } else {
              calendarWidget = WeekView(
                key: ValueKey('week_${uiState.baseDate}_${uiState.currentView}_${dataState.checkedPlaceIds.length}'),
                controller: controller,
                minDay: uiState.baseDate.subtract(const Duration(days: 28)),
                maxDay: uiState.baseDate.add(const Duration(days: 84)),
                initialDay: uiState.baseDate,
                scrollOffset: initialScrollOffset,
                startDay: uiState.currentView == CalendarViewType.threeDay
                    ? WeekDays.values[uiState.baseDate.weekday - 1]
                    : WeekDays.monday,
                weekDays: weekDays,
                heightPerMinute: 1,
                scrollPhysics: const ClampingScrollPhysics(),
                pageViewPhysics: const NeverScrollableScrollPhysics(),
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                headerStyle: HeaderStyle(decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor)),
                weekTitleBackgroundColor: const Color(0xFF1565C0),
                eventArranger: const StackEventArranger(),
                eventTileBuilder: (date, events, boundary, startDuration, endDuration) =>
                    CalendarEventTileWidget(
                  date: date,
                  events: events,
                  boundary: boundary,
                  startDuration: startDuration,
                  endDuration: endDuration,
                ),
                fullDayEventBuilder: (events, date) =>
                    FullDayEventWidget(events: events, date: date),
                showLiveTimeLineInAllDays: true,
                weekPageHeaderBuilder: (start, end) => const SizedBox.shrink(),
                weekNumberBuilder: (date) => const SizedBox.shrink(),
                hourIndicatorSettings: HourIndicatorSettings(color: Theme.of(context).dividerColor),
                liveTimeIndicatorSettings: LiveTimeIndicatorSettings(color: Theme.of(context).colorScheme.primary, showBullet: false),
                timeLineBuilder: (date) => _buildTimeLineLabel(
                  date, use24HourFormat, Theme.of(context).textTheme.bodySmall?.color ?? textSmallColor,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _weekDayShortName(date.weekday),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${date.month}/${date.day}',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
                          context.read<CalendarUiCubit>().navigateDate(uiState.baseDate.subtract(Duration(days: daysToAdvance)));
                        },
                      ),
                      Expanded(
                        child: Text(
                          _buildHeaderText(uiState.currentView, uiState.baseDate),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          context.read<CalendarUiCubit>().navigateDate(uiState.baseDate.add(Duration(days: daysToAdvance)));
                        },
                      ),
                      if (!isShowingToday)
                        TextButton.icon(
                          onPressed: () => context.read<CalendarUiCubit>().navigateDate(DateTime.now()),
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
        );
      }
    );
  }

  Widget _buildPlacesSidebar(BuildContext context, CalendarDataState dataState) {
    if (dataState.status == CalendarDataStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dataState.savedPlaces.isEmpty) {
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
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      itemCount: dataState.savedPlaces.length,
      itemBuilder: (context, index) {
        final sp = dataState.savedPlaces[index];
        final isChecked = dataState.checkedPlaceIds.contains(sp.place.tomtomId);
        final color = _colorForPlace(sp, index);
        final iconName = sp.icon ?? 'star';
        final iconData = _availableIcons[iconName] ?? Icons.star;

        return CheckboxListTile(
          value: isChecked,
          onChanged: (val) {
            context.read<CalendarDataBloc>().add(TogglePlaceFilter(sp.place.tomtomId));
          },
          secondary: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(iconData, color: Colors.white, size: 20),
          ),
          title: Text(
            _displayName(sp),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: color,
        );
      },
    );
  }

  Widget _buildDeviceCalendarsSidebar(BuildContext context, CalendarDataState dataState) {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(Icons.devices_other, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              'Device sync is available on Mobile only. For Web/Desktop, consider cloud sync (coming soon).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          ],
        ),
      );
    }

    if (!dataState.hasCalendarPermission) {
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
              onPressed: () => context.read<CalendarDataBloc>().add(const InitDeviceCalendar(fromButton: true)),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (dataState.deviceCalendars.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No calendars found on this device.', textAlign: TextAlign.center),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: dataState.deviceCalendars.length,
      itemBuilder: (context, index) {
        final cal = dataState.deviceCalendars[index];
        final isChecked = dataState.checkedCalendarIds.contains(cal.id);
        final color = cal.color != null ? Color(cal.color!) : Colors.blue;

        return CheckboxListTile(
          value: isChecked,
          onChanged: (val) {
            if (cal.id != null) {
              context.read<CalendarDataBloc>().add(ToggleDeviceCalendar(cal.id!));
            }
          },
          secondary: Container(
            width: 12, height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          title: Text(
            cal.name ?? 'Unnamed Calendar',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: color,
        );
      },
    );
  }

  Widget _buildRemoteSubscriptionSidebar(BuildContext context, CalendarDataState dataState) {
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
              ),
              const Spacer(),
              if (hasUrl)
                IconButton(
                  icon: dataState.isLoadingRemote
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  onPressed: dataState.isLoadingRemote ? null : () => context.read<CalendarDataBloc>().add(LoadRemoteEvents(url)),
                ),
              IconButton(
                icon: const Icon(Icons.settings, size: 18),
                onPressed: () => _showSubscriptionDialog(context, url),
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
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Text(
              'Syncing with ${dataState.remoteEvents.length} events.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }

  void _showSubscriptionDialog(BuildContext context, String? currentUrl) {
    final controller = TextEditingController(text: currentUrl ?? '');
    final authBloc = context.read<AuthBloc>();
    final dataBloc = context.read<CalendarDataBloc>();

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
              final authState = authBloc.state;
              if (authState is AuthAuthenticated) {
                final updatedUser = User(
                  id: authState.user.id,
                  username: authState.user.username,
                  calendarSubscriptionUrl: controller.text,
                );
                authBloc.add(ProfileUpdateRequested(updatedUser: updatedUser));
              }
              Navigator.pop(context);
              Future.delayed(const Duration(seconds: 1), () {
                dataBloc.add(LoadRemoteEvents(controller.text));
              });
            },
            child: const Text('Save & Sync'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final textSmallColor = isDark ? Colors.white70 : Colors.black87;
    final use24HourFormat = context.watch<PreferencesCubit>().state.use24HourFormat;
    final isMobile = MediaQuery.of(context).size.width < 800;

    return BlocBuilder<CalendarUiCubit, CalendarUiState>(
      builder: (context, uiState) {
        return BlocBuilder<CalendarDataBloc, CalendarDataState>(
          builder: (context, dataState) {
            Widget sidebarContent = ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'My Places',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () => context.read<CalendarDataBloc>().add(LoadSavedPlaces()),
                      ),
                    ],
                  ),
                ),
                _buildPlacesSidebar(context, dataState),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Device Calendars',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const Spacer(),
                      if (dataState.hasCalendarPermission)
                        IconButton(
                          icon: const Icon(Icons.sync, size: 18),
                          onPressed: () => context.read<CalendarDataBloc>().add(const InitDeviceCalendar(fromButton: true)),
                        ),
                    ],
                  ),
                ),
                _buildDeviceCalendarsSidebar(context, dataState),
                const Divider(),
                _buildRemoteSubscriptionSidebar(context, dataState),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Imported Events',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const Spacer(),
                      if (dataState.importedEvents.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => context.read<CalendarDataBloc>().add(ClearImportedEvents()),
                          tooltip: 'Clear Imported',
                        ),
                      IconButton(
                        icon: const Icon(Icons.file_upload, size: 18),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['ics'], withData: true);
                          if (result != null && result.files.single.bytes != null) {
                            final icsString = utf8.decode(result.files.single.bytes!);
                            if (context.mounted) {
                              context.read<CalendarDataBloc>().add(ImportIcalFile(icsString));
                            }
                          }
                        },
                        tooltip: 'Import .ics file',
                      ),
                    ],
                  ),
                ),
                if (dataState.importedEvents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No events imported. Upload a .ics file to see external events.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      'Displaying ${dataState.importedEvents.length} imported events.',
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
                    child: _buildCalendarOptions(context, uiState.currentView),
                  ),
                  if (isMobile)
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.filter_list),
                        onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                      ),
                    ),
                ],
              ),
              endDrawer: isMobile ? Drawer(child: sidebarContent) : null,
              body: isMobile
                  ? _buildCalendar(context, textColor, textSmallColor, use24HourFormat)
                  : Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildCalendar(context, textColor, textSmallColor, use24HourFormat),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 1, child: sidebarContent),
                      ],
                    ),
            );
          }
        );
      }
    );
  }
}





