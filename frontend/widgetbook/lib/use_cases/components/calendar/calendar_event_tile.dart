import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:frontend/components/calendar/calendar_event_tile.dart';
import 'package:frontend/utils/places_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/stage.dart';

final _day = DateTime(2026, 3, 9);

@widgetbook.UseCase(name: 'Business block', type: CalendarEventTileWidget)
Widget buildCalendarEventTileBusinessUseCase(BuildContext context) {
  final title = context.knobs.string(
    label: 'Title',
    initialValue: '3 places open',
  );
  final color = context.knobs.color(
    label: 'Place color',
    initialValue: const Color(0xFFB14E27),
  );
  return _TileStage(
    event: CalendarEventData(
      title: title,
      date: _day,
      startTime: _day.add(const Duration(hours: 15)),
      endTime: _day.add(const Duration(hours: 18)),
      color: color,
    ),
  );
}

@widgetbook.UseCase(name: 'Personal event', type: CalendarEventTileWidget)
Widget buildCalendarEventTilePersonalUseCase(BuildContext context) {
  final title = context.knobs.string(
    label: 'Title',
    initialValue: 'Design review',
  );
  // As CalendarScreen adds them: tagged personal, in theme.inkMuted.
  return _TileStage(
    event: CalendarEventData(
      title: title,
      date: _day,
      startTime: _day.add(const Duration(hours: 13)),
      endTime: _day.add(const Duration(hours: 14, minutes: 30)),
      color: context.places.inkMuted,
      event: CalendarBlockKind.personal,
    ),
  );
}

class _TileStage extends StatelessWidget {
  const _TileStage({required this.event});

  final CalendarEventData<Object?> event;

  @override
  Widget build(BuildContext context) {
    final height = context.knobs.double.slider(
      label: 'Tile height',
      description: 'Simulates the event duration in the day grid.',
      initialValue: 120,
      min: 24,
      max: 240,
    );
    const width = 160.0;
    return ComponentStage(
      child: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: CalendarEventTileWidget(
            date: event.date,
            events: [event],
            boundary: Rect.fromLTWH(0, 0, width, height),
            startDuration: event.startTime!,
            endDuration: event.endTime!,
          ),
        ),
      ),
    );
  }
}

@widgetbook.UseCase(name: 'Single event', type: FullDayEventWidget)
Widget buildFullDayEventSingleUseCase(BuildContext context) {
  return ComponentStage(
    child: FullDayEventWidget(
      date: _day,
      events: [
        CalendarEventData(
          title: context.knobs.string(
            label: 'Title',
            initialValue: 'Out of office',
          ),
          date: _day,
          color: Colors.blueGrey.withValues(alpha: 0.6),
        ),
      ],
    ),
  );
}

@widgetbook.UseCase(name: 'Multiple events', type: FullDayEventWidget)
Widget buildFullDayEventMultipleUseCase(BuildContext context) {
  final count = context.knobs.int.slider(
    label: 'Event count',
    initialValue: 3,
    min: 2,
    max: 6,
  );
  const titles = [
    'Out of office',
    'Public holiday',
    'Sam’s birthday',
    'Conference',
    'Moving day',
    'Recital',
  ];
  return ComponentStage(
    child: FullDayEventWidget(
      date: _day,
      events: [
        for (var i = 0; i < count; i++)
          CalendarEventData(
            title: titles[i],
            date: _day,
            color: Colors.primaries[i * 3 % Colors.primaries.length].withValues(
              alpha: 0.6,
            ),
          ),
      ],
    ),
  );
}
