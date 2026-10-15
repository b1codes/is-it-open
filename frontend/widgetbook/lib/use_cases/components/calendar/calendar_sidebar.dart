import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/components/calendar/calendar_sidebar.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/utils/graphics_helper.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';

const _palette = [
  Color(0xFFB14E27),
  Color(0xFFD99B52),
  Color(0xFF8F7A6A),
  Color(0xFF6B5344),
];

// Same rule CalendarScreen uses: the saved hex color, else a palette slot.
Color _colorForPlace(SavedPlace sp, int index) {
  final hex = sp.color;
  if (hex != null && hex.isNotEmpty) {
    final value = int.tryParse(hex, radix: 16);
    if (value != null) return Color(value);
  }
  return _palette[index % _palette.length];
}

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
                  colorForPlace: _colorForPlace,
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
