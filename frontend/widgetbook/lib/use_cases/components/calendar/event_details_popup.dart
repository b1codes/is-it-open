import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:frontend/components/calendar/event_details_popup.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/route_harness.dart';
import '../../support/stage.dart';

final _day = DateTime(2026, 3, 9);

@widgetbook.UseCase(name: 'Timed event', type: EventDetailsPopup)
Widget buildEventDetailsPopupTimedUseCase(BuildContext context) {
  return _PopupStage(
    popup: EventDetailsPopup(
      event: CalendarEventData(
        title: context.knobs.string(
          label: 'Title',
          initialValue: 'Dinner with Sam',
        ),
        description: context.knobs.string(
          label: 'Description',
          initialValue: 'Corner Bistro. Ask for the back booth.',
          maxLines: 3,
        ),
        date: _day,
        startTime: _day.add(const Duration(hours: 19)),
        endTime: _day.add(const Duration(hours: 21)),
        color: Colors.teal,
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'All-day event', type: EventDetailsPopup)
Widget buildEventDetailsPopupAllDayUseCase(BuildContext context) {
  return _PopupStage(
    popup: EventDetailsPopup(
      event: CalendarEventData(
        title: 'Out of office',
        date: _day,
        endDate: _day.add(const Duration(days: 2)),
        color: Colors.blueGrey,
      ),
    ),
  );
}

// The popup is a Dialog whose close button pops its route, so it is hosted
// on the harness over a busy backdrop that shows off the glass blur.
class _PopupStage extends StatelessWidget {
  const _PopupStage({required this.popup});

  final Widget popup;

  @override
  Widget build(BuildContext context) {
    return RouteHarness(
      builder: (_) => Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: GlassBackdrop()),
            popup,
          ],
        ),
      ),
    );
  }
}
