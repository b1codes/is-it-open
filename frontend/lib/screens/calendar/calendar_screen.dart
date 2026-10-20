import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';

import '../../components/calendar/calendar_view_stack.dart';
import '../../components/calendar/calendar_sidebar.dart';
import '../../components/calendar/planner_view.dart';
import '../../models/saved_place.dart';

import '../../bloc/calendar/calendar_ui_cubit.dart';
import '../../bloc/preferences/preferences_cubit.dart';
import '../../bloc/calendar/calendar_ui_state.dart';
import '../../bloc/calendar/calendar_data_bloc.dart';
import '../../bloc/calendar/calendar_data_state.dart';
import '../../utils/availability_calculator.dart';
import '../../utils/graphics_helper.dart';
import '../../utils/places_theme.dart';
import '../../components/core/refractive_glass.dart';

class CalendarScreen extends StatelessWidget {
  final bool embedded;
  final ScrollController? scrollController;

  const CalendarScreen({
    super.key,
    this.embedded = false,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final defaultCollapsed = width >= 600 && width < 1024;
    return BlocProvider<CalendarUiCubit>(
      create: (context) =>
          CalendarUiCubit(initialSidebarCollapsed: defaultCollapsed),
      child: _CalendarScreenView(embedded: embedded),
    );
  }
}

class _CalendarScreenView extends StatelessWidget {
  final bool embedded;
  const _CalendarScreenView({required this.embedded});

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
      child: _CalendarScreenContent(embedded: embedded),
    );
  }
}

class _CalendarScreenContent extends StatelessWidget {
  final bool embedded;
  const _CalendarScreenContent({required this.embedded});

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

  List<Map<String, dynamic>> _preparePersonalEvents(CalendarDataState state) {
    final allEvents = [
      ...state.deviceEvents,
      ...state.importedEvents,
      ...state.remoteEvents,
    ];

    return allEvents
        .where((e) => e.startTime != null && e.endTime != null)
        .map(
          (e) => {
            'id': e.title,
            'title': e.title,
            'startTime': e.startTime!,
            'endTime': e.endTime!,
            'originalEvent': e,
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _prepareBusinessBlocks(
    CalendarDataState dataState,
    DateTime baseDate,
  ) {
    final List<Map<String, dynamic>> blocks = [];
    final startOfRange = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day - 14,
    );

    for (final sp in dataState.savedPlaces) {
      if (!dataState.checkedPlaceIds.contains(sp.place.tomtomId)) continue;

      for (int dayOffset = 0; dayOffset <= 42; dayOffset++) {
        // Calendar arithmetic, so a DST change can't repeat or skip a day.
        final date = DateTime(
          startOfRange.year,
          startOfRange.month,
          startOfRange.day + dayOffset,
        );
        // BusinessHours days are Mon=0..Sun=6; DateTime.weekday is Mon=1..Sun=7.
        final dayOfWeek = date.weekday - 1;

        for (final hours in sp.place.hours) {
          if (hours.dayOfWeek == dayOfWeek) {
            // Strip timezone and use naive DateTime for business hours
            final startTime = DateTime(
              date.year,
              date.month,
              date.day,
              hours.openTime.hour,
              hours.openTime.minute,
            );
            var endTime = DateTime(
              date.year,
              date.month,
              date.day,
              hours.closeTime.hour,
              hours.closeTime.minute,
            );
            if (endTime.isBefore(startTime)) {
              endTime = endTime.add(const Duration(days: 1));
            }

            blocks.add({
              'id': sp.place.tomtomId,
              'startTime': startTime,
              'endTime': endTime,
            });
          }
        }
      }
    }
    return blocks;
  }

  EventController<Object?> _buildLegacyController(
    CalendarDataState dataState,
    CalendarUiState uiState,
    List<AvailabilityWindow> windows,
    Color personalEventColor,
  ) {
    final controller = EventController<Object?>();

    // 1. Add Open Windows as events
    if (uiState.showBusinessHours) {
      for (final window in windows) {
        controller.add(
          CalendarEventData(
            title: window.label,
            date: window.date,
            startTime: window.startTime,
            endTime: window.endTime,
            color: PlacesTheme.light.anchor.withValues(alpha: 0.15),
          ),
        );
      }
    }

    // 2. Add Personal Events
    if (uiState.showPersonalEvents) {
      final allPersonalEvents = [
        ...dataState.deviceEvents,
        ...dataState.importedEvents,
        ...dataState.remoteEvents,
      ];
      for (final event in allPersonalEvents) {
        controller.add(
          CalendarEventData(
            title: event.title,
            description: event.description,
            date: event.date,
            startTime: event.startTime,
            endTime: event.endTime,
            color: personalEventColor,
            event: event.event,
          ),
        );
      }
    }

    return controller;
  }

  void _showSchedulingSheet(
    BuildContext context,
    AvailabilityWindow window,
    CalendarDataState dataState,
    PlacesTheme theme,
  ) {
    final availablePlaces = dataState.savedPlaces
        .where((sp) => window.placeIds.contains(sp.place.tomtomId))
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return RefractiveGlass(
              borderRadius: PlacesRadius.lg,
              opacity: 0.15,
              child: Container(
                color: theme.paper.withValues(alpha: 0.8),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.ash,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Schedule Errand',
                                  style: PlacesType.headline(theme.ink),
                                ),
                                Text(
                                  '${availablePlaces.length} options for this window',
                                  style: PlacesType.label(theme.inkMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: availablePlaces.length,
                        itemBuilder: (context, index) {
                          final sp = availablePlaces[index];
                          return _PlaceSelectionTile(
                            sp: sp,
                            theme: theme,
                            onTap: () {
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return BlocBuilder<CalendarUiCubit, CalendarUiState>(
      builder: (context, uiState) {
        return BlocBuilder<CalendarDataBloc, CalendarDataState>(
          builder: (context, dataState) {
            final personalEvents = _preparePersonalEvents(dataState);
            final businessBlocks = _prepareBusinessBlocks(
              dataState,
              uiState.baseDate,
            );

            // Calculate windows using toggled state
            final windows = AvailabilityCalculator.calculateAvailableWindows(
              businessBlocks: businessBlocks,
              personalEvents: uiState.showPersonalEvents ? personalEvents : [],
            );

            Widget mainContent;
            if (uiState.currentView == CalendarViewType.week) {
              mainContent = CalendarViewStackWidget(
                uiState: uiState,
                controller: _buildLegacyController(
                  dataState,
                  uiState,
                  windows,
                  // Exactly inkMuted: CalendarEventTileWidget styles an
                  // event as personal by matching this color.
                  theme.inkMuted,
                ),
                checkedPlacesCount: dataState.checkedPlaceIds.length,
                textColor: theme.ink,
                textSmallColor: theme.inkMuted,
                use24HourFormat: context
                    .watch<PreferencesCubit>()
                    .state
                    .use24HourFormat,
              );
            } else {
              mainContent = PlannerView(
                baseDate: uiState.baseDate,
                dayCount: uiState.currentView == CalendarViewType.threeDay
                    ? 3
                    : 1,
                windows: windows,
                personalEvents: uiState.showPersonalEvents
                    ? personalEvents
                    : [],
                onNavigateLeft: () {
                  final days = uiState.currentView == CalendarViewType.threeDay
                      ? 3
                      : 1;
                  context.read<CalendarUiCubit>().navigateDate(
                    uiState.baseDate.subtract(Duration(days: days)),
                  );
                },
                onNavigateRight: () {
                  final days = uiState.currentView == CalendarViewType.threeDay
                      ? 3
                      : 1;
                  context.read<CalendarUiCubit>().navigateDate(
                    uiState.baseDate.add(Duration(days: days)),
                  );
                },
                onNavigateToday: () {
                  context.read<CalendarUiCubit>().navigateDate(clock.now());
                },
                onWindowTap: (window) =>
                    _showSchedulingSheet(context, window, dataState, theme),
              );
            }

            if (embedded) {
              return Container(color: theme.paper, child: mainContent);
            }

            return Scaffold(
              backgroundColor: theme.paper,
              appBar: AppBar(
                title: Text('Plan', style: PlacesType.headline(theme.ink)),
                backgroundColor: theme.paper,
                elevation: 0,
                scrolledUnderElevation: 0,
                iconTheme: IconThemeData(color: theme.ink),
                actions: [
                  _buildToggleAction(
                    context: context,
                    isActive: uiState.showBusinessHours,
                    icon: Icons.business_center,
                    label: 'Places',
                    activeColor: theme.anchor,
                    onTap: () =>
                        context.read<CalendarUiCubit>().toggleBusinessHours(),
                  ),
                  const SizedBox(width: 8),
                  _buildToggleAction(
                    context: context,
                    isActive: uiState.showPersonalEvents,
                    icon: Icons.person,
                    label: 'Personal',
                    activeColor: theme.inkMuted,
                    onTap: () =>
                        context.read<CalendarUiCubit>().togglePersonalEvents(),
                  ),
                  if (isMobile) ...[
                    const SizedBox(width: 8),
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: Icon(Icons.filter_list, color: theme.ink),
                        tooltip: 'Calendar options',
                        onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        uiState.isSidebarCollapsed
                            ? Icons.menu_open
                            : Icons.menu,
                        color: theme.ink,
                      ),
                      onPressed: () =>
                          context.read<CalendarUiCubit>().toggleSidebar(),
                      tooltip: uiState.isSidebarCollapsed
                          ? 'Expand Sidebar'
                          : 'Collapse Sidebar',
                    ),
                  ],
                ],
              ),
              endDrawer: isMobile
                  ? Drawer(
                      backgroundColor: theme.paper,
                      child: SafeArea(
                        child: CalendarSidebarWidget(
                          dataState: dataState,
                          colorForPlace: GraphicsHelper.colorForSavedPlace,
                          availableIcons: _availableIcons,
                          isCollapsed: false,
                        ),
                      ),
                    )
                  : null,
              body: Row(
                children: [
                  Expanded(child: mainContent),
                  if (!isMobile) ...[
                    VerticalDivider(width: 1, color: theme.ashSoft),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: uiState.isSidebarCollapsed ? 64 : 320,
                      color: theme.paperRaised,
                      child: CalendarSidebarWidget(
                        dataState: dataState,
                        colorForPlace: GraphicsHelper.colorForSavedPlace,
                        availableIcons: _availableIcons,
                        isCollapsed: uiState.isSidebarCollapsed,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildToggleAction({
    required BuildContext context,
    required bool isActive,
    required IconData icon,
    required String label,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final theme = context.places;
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(PlacesRadius.lg),
              border: Border.all(
                color: isActive
                    ? activeColor.withValues(alpha: 0.3)
                    : theme.ash,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive ? activeColor : theme.inkMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: PlacesType.label(isActive ? activeColor : theme.ink)
                      .copyWith(
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing: 0,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceSelectionTile extends StatelessWidget {
  final SavedPlace sp;
  final PlacesTheme theme;
  final VoidCallback onTap;

  const _PlaceSelectionTile({
    required this.sp,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PlacesRadius.md),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.paperRaised,
            borderRadius: BorderRadius.circular(PlacesRadius.md),
            border: Border.all(color: theme.ashSoft, width: 0.5),
          ),
          child: Row(
            children: [
              GraphicsHelper.buildProfileGraphic(sp, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sp.customName ?? sp.place.name,
                      style: PlacesType.title(theme.ink),
                    ),
                    Text(
                      'Open today',
                      style: PlacesType.bodySmall(theme.inkMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_circle_outline, color: theme.anchor, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
