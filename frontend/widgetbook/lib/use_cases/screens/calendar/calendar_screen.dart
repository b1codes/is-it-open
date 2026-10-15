import 'package:flutter/material.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../../mocks/sample_data.dart';
import '../../support/embedded.dart';

@widgetbook.UseCase(name: 'Default', type: CalendarScreen)
Widget buildCalendarScreenUseCase(BuildContext context) {
  final embedded = embeddedKnob(context);
  final checkedCount = context.knobs.int.slider(
    label: 'Places checked',
    initialValue: 2,
    max: sampleSavedPlaces.length,
  );
  final withEvents = context.knobs.boolean(
    label: 'Personal events',
    initialValue: true,
  );
  return MockAppScope(
    calendarData: CalendarDataState(
      status: CalendarDataStatus.loaded,
      savedPlaces: sampleSavedPlaces,
      checkedPlaceIds: {
        for (final sp in sampleSavedPlaces.take(checkedCount))
          sp.place.tomtomId,
      },
      importedEvents: withEvents ? currentWeekEvents : const [],
    ),
    child: embedIfNeeded(
      embedded: embedded,
      child: CalendarScreen(embedded: embedded),
    ),
  );
}

@widgetbook.UseCase(name: 'No saved places', type: CalendarScreen)
Widget buildCalendarScreenEmptyUseCase(BuildContext context) {
  return const MockAppScope(
    bookmarks: [],
    calendarData: CalendarDataState(status: CalendarDataStatus.loaded),
    child: CalendarScreen(),
  );
}

@widgetbook.UseCase(name: 'Loading places', type: CalendarScreen)
Widget buildCalendarScreenLoadingUseCase(BuildContext context) {
  return const MockAppScope(
    calendarData: CalendarDataState(status: CalendarDataStatus.loading),
    child: CalendarScreen(),
  );
}
