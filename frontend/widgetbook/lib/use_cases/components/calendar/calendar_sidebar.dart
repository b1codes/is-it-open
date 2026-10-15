import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/components/calendar/calendar_sidebar.dart';
import 'package:frontend/utils/graphics_helper.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';

enum _SidebarData { loaded, loading, empty }

@widgetbook.UseCase(name: 'Default', type: CalendarSidebarWidget)
Widget buildCalendarSidebarUseCase(BuildContext context) {
  final collapsed = context.knobs.boolean(label: 'Collapsed');
  final data = context.knobs.object.segmented<_SidebarData>(
    label: 'Saved places',
    options: _SidebarData.values,
    labelBuilder: (d) => d.name,
  );
  final remoteSync = context.knobs.boolean(
    label: 'Remote calendar subscribed',
    initialValue: true,
  );

  final seed = switch (data) {
    _SidebarData.loaded => CalendarDataState(
      status: CalendarDataStatus.loaded,
      savedPlaces: sampleSavedPlaces,
      checkedPlaceIds: {
        sampleSavedPlaces[0].place.tomtomId,
        sampleSavedPlaces[2].place.tomtomId,
      },
      importedEvents: currentWeekEvents,
    ),
    _SidebarData.loading => const CalendarDataState(
      status: CalendarDataStatus.loading,
    ),
    _SidebarData.empty => const CalendarDataState(
      status: CalendarDataStatus.loaded,
    ),
  };

  return MockAppScope(
    calendarData: seed,
    authState: AuthAuthenticated(user: remoteSync ? demoUser : minimalUser),
    child: Scaffold(
      body: Row(
        children: [
          const Expanded(child: SizedBox.expand()),
          VerticalDivider(width: 1, color: context.places.ashSoft),
          // Docked on the right at CalendarScreen's widths.
          SizedBox(
            width: collapsed ? 64 : 320,
            child: Material(
              color: context.places.paperRaised,
              // Live state so the place checkboxes and import actions work.
              child: BlocBuilder<CalendarDataBloc, CalendarDataState>(
                builder: (context, state) => CalendarSidebarWidget(
                  dataState: state,
                  colorForPlace: GraphicsHelper.colorForSavedPlace,
                  availableIcons: GraphicsHelper.availableIcons,
                  isCollapsed: collapsed,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
