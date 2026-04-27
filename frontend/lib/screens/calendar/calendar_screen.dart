import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';
import '../../components/calendar/calendar_header.dart';
import '../../components/calendar/calendar_view_stack.dart';
import '../../components/calendar/calendar_sidebar.dart';
import '../../models/saved_place.dart';
import '../../bloc/preferences/preferences_cubit.dart';

import '../../bloc/calendar/calendar_ui_cubit.dart';
import '../../bloc/calendar/calendar_ui_state.dart';
import '../../bloc/calendar/calendar_data_bloc.dart';
import '../../bloc/calendar/calendar_data_state.dart';
import '../../utils/availability_calculator.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CalendarUiCubit>(
      create: (context) => CalendarUiCubit(),
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
          current.errorMessage != null &&
          current.errorMessage != previous.errorMessage,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
        }
      },
      child: const _CalendarScreenContent(),
    );
  }
}

class _CalendarScreenContent extends StatelessWidget {
  const _CalendarScreenContent();

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

  Color _colorForPlace(SavedPlace sp, int index) {
    if (sp.color != null && sp.color!.isNotEmpty) {
      try {
        return Color(int.parse(sp.color!, radix: 16));
      } catch (_) {}
    }
    return _defaultPalette[index % _defaultPalette.length];
  }

  EventController<Object?> _buildEventController(
    CalendarDataState dataState,
    CalendarUiState uiState,
  ) {
    final controller = EventController<Object?>();
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    List<CalendarEventData<Object?>> businessBlocks = [];

    if (uiState.showBusinessHours) {
      int colorIndex = 0;
      for (final sp in dataState.savedPlaces) {
        if (!dataState.checkedPlaceIds.contains(sp.place.tomtomId)) {
          colorIndex++;
          continue;
        }

        final color = _colorForPlace(
          sp,
          colorIndex,
        ).withValues(alpha: 1.0); // Solid for contrast
        final label = displayName(sp);

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

            businessBlocks.add(
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
    }

    final allPersonalEvents = [
      ...dataState.deviceEvents,
      ...dataState.importedEvents,
      ...dataState.remoteEvents,
    ];

    final timedPersonalEvents = allPersonalEvents
        .where((e) => e.startTime != null && e.endTime != null)
        .toList();

    if (uiState.showBusinessHours && uiState.showPersonalEvents) {
      final availableWindows = AvailabilityCalculator.calculateAvailableWindows(
        businessBlocks,
        timedPersonalEvents,
      );
      controller.addAll(availableWindows);
    } else if (uiState.showBusinessHours) {
      controller.addAll(businessBlocks);
    }

    if (uiState.showPersonalEvents) {
      controller.addAll(allPersonalEvents);
    }

    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final use24HourFormat = context
        .watch<PreferencesCubit>()
        .state
        .use24HourFormat;
    final isMobile = MediaQuery.of(context).size.width < 800;

    return BlocBuilder<CalendarUiCubit, CalendarUiState>(
      builder: (context, uiState) {
        return BlocBuilder<CalendarDataBloc, CalendarDataState>(
          builder: (context, dataState) {
            final controller = _buildEventController(dataState, uiState);

            Widget sidebarContent = CalendarSidebarWidget(
              dataState: dataState,
              colorForPlace: _colorForPlace,
              availableIcons: _availableIcons,
              isCollapsed: uiState.isSidebarCollapsed,
            );

            Widget calendarContent = CalendarViewStackWidget(
              uiState: uiState,
              controller: controller,
              checkedPlacesCount: dataState.checkedPlaceIds.length,
              textColor: colorScheme.onSurface,
              textSmallColor: colorScheme.onSurfaceVariant,
              use24HourFormat: use24HourFormat,
            );

            return Scaffold(
              appBar: AppBar(
                title: const Text('Calendar'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: Icon(
                      uiState.showBusinessHours
                          ? Icons.business_center
                          : Icons.business_center_outlined,
                      color: uiState.showBusinessHours
                          ? Colors.green
                          : Colors.grey,
                    ),
                    tooltip: 'Toggle Business Hours',
                    onPressed: () {
                      context.read<CalendarUiCubit>().toggleBusinessHours();
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      uiState.showPersonalEvents
                          ? Icons.person
                          : Icons.person_outline,
                      color: uiState.showPersonalEvents
                          ? Colors.blue
                          : Colors.grey,
                    ),
                    tooltip: 'Toggle Personal Events',
                    onPressed: () {
                      context.read<CalendarUiCubit>().togglePersonalEvents();
                    },
                  ),
                  if (!isMobile)
                    IconButton(
                      icon: Icon(
                        uiState.isSidebarCollapsed
                            ? Icons.chevron_left
                            : Icons.chevron_right,
                      ),
                      tooltip: uiState.isSidebarCollapsed
                          ? 'Expand Sidebar'
                          : 'Collapse Sidebar',
                      onPressed: () {
                        context.read<CalendarUiCubit>().toggleSidebar();
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: CalendarHeaderWidget(
                      currentView: uiState.currentView,
                    ),
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
                  ? calendarContent
                  : Row(
                      children: [
                        Expanded(child: calendarContent),
                        const VerticalDivider(width: 1),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: uiState.isSidebarCollapsed ? 64 : 300,
                          child: sidebarContent,
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}
