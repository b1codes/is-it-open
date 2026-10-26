import 'package:calendar_view/calendar_view.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_ui_cubit.dart';
import 'package:frontend/bloc/calendar/calendar_ui_state.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';
import 'package:frontend/components/calendar/calendar_view_stack.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/sample_data.dart';

@widgetbook.UseCase(name: 'Default', type: CalendarViewStackWidget)
Widget buildCalendarViewStackUseCase(BuildContext context) {
  final view = context.knobs.object.segmented<CalendarViewType>(
    label: 'View',
    options: CalendarViewType.values,
    initialOption: CalendarViewType.week,
    labelBuilder: (v) => v.name,
  );
  final showBusinessHours = context.knobs.boolean(
    label: 'Show open windows',
    initialValue: true,
  );
  final showPersonalEvents = context.knobs.boolean(
    label: 'Show personal events',
    initialValue: true,
  );
  final use24HourFormat = context.knobs.boolean(label: '24-hour clock');

  return BlocProvider(
    key: ValueKey(view),
    create: (_) => CalendarUiCubit()..changeViewType(view),
    child: Scaffold(
      body: BlocBuilder<CalendarUiCubit, CalendarUiState>(
        builder: (context, uiState) => _ControllerHost(
          uiState: uiState,
          showBusinessHours: showBusinessHours,
          showPersonalEvents: showPersonalEvents,
          use24HourFormat: use24HourFormat,
        ),
      ),
    ),
  );
}

// Owns the EventController and fills it the way CalendarScreen does: open
// windows tinted with the anchor color, personal events in inkMuted, each
// tagged with its CalendarBlockKind.
class _ControllerHost extends StatefulWidget {
  const _ControllerHost({
    required this.uiState,
    required this.showBusinessHours,
    required this.showPersonalEvents,
    required this.use24HourFormat,
  });

  final CalendarUiState uiState;
  final bool showBusinessHours;
  final bool showPersonalEvents;
  final bool use24HourFormat;

  @override
  State<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends State<_ControllerHost> {
  final _controller = EventController<Object?>();
  int _windowCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fill();
  }

  @override
  void didUpdateWidget(_ControllerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showBusinessHours != widget.showBusinessHours ||
        oldWidget.showPersonalEvents != widget.showPersonalEvents) {
      _fill();
    }
  }

  void _fill() {
    final theme = context.places;
    _controller.removeWhere((_) => true);
    final windows = sampleAvailabilityWindows(clock.now(), dayCount: 7);
    _windowCount = windows.length;
    if (widget.showBusinessHours) {
      _controller.addAll([
        for (final window in windows)
          CalendarEventData(
            title: '${window.placeCount} places open',
            date: window.date,
            startTime: window.startTime,
            endTime: window.endTime,
            color: PlacesTheme.light.anchor.withValues(alpha: 0.15),
            event: CalendarBlockKind.openWindow,
          ),
      ]);
    }
    if (widget.showPersonalEvents) {
      _controller.addAll([
        for (final event in currentWeekEvents)
          CalendarEventData(
            title: event.title,
            description: event.description,
            date: event.date,
            endDate: event.endDate,
            startTime: event.startTime,
            endTime: event.endTime,
            color: theme.inkMuted,
            event: CalendarBlockKind.personal,
          ),
      ]);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return CalendarViewStackWidget(
      uiState: widget.uiState,
      controller: _controller,
      checkedPlacesCount: widget.showBusinessHours ? _windowCount : 0,
      textColor: theme.ink,
      textSmallColor: theme.inkMuted,
      use24HourFormat: widget.use24HourFormat,
    );
  }
}
