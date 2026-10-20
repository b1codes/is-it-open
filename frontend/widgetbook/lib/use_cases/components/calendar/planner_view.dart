import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:frontend/components/calendar/planner_view.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/sample_data.dart';
import '../../support/stage.dart';

@widgetbook.UseCase(name: 'Default', type: PlannerView)
Widget buildPlannerViewUseCase(BuildContext context) {
  final dayCount = context.knobs.object.segmented<int>(
    label: 'Days',
    options: const [1, 3],
    initialOption: 3,
    labelBuilder: (d) => d == 1 ? 'Single day' : 'Three day',
  );
  final showWindows = context.knobs.boolean(
    label: 'Open windows',
    initialValue: true,
  );
  final showPersonal = context.knobs.boolean(
    label: 'Personal events',
    initialValue: true,
  );
  return _PlannerHost(
    dayCount: dayCount,
    showWindows: showWindows,
    showPersonal: showPersonal,
  );
}

@widgetbook.UseCase(name: 'Empty', type: PlannerView)
Widget buildPlannerViewEmptyUseCase(BuildContext context) {
  return const _PlannerHost(
    dayCount: 3,
    showWindows: false,
    showPersonal: false,
  );
}

// Holds the base date so the navigation callbacks actually page the view.
class _PlannerHost extends StatefulWidget {
  const _PlannerHost({
    required this.dayCount,
    required this.showWindows,
    required this.showPersonal,
  });

  final int dayCount;
  final bool showWindows;
  final bool showPersonal;

  @override
  State<_PlannerHost> createState() => _PlannerHostState();
}

class _PlannerHostState extends State<_PlannerHost> {
  DateTime _baseDate = dateOnly(clock.now());

  void _shift(int days) =>
      setState(() => _baseDate = _baseDate.add(Duration(days: days)));

  @override
  Widget build(BuildContext context) {
    final anchor = dateOnly(clock.now());
    return Scaffold(
      body: Builder(
        builder: (context) => PlannerView(
          baseDate: _baseDate,
          dayCount: widget.dayCount,
          windows: widget.showWindows
              ? sampleAvailabilityWindows(anchor, dayCount: 7)
              : const [],
          personalEvents: widget.showPersonal
              ? samplePersonalEvents(anchor)
              : const [],
          onNavigateLeft: () => _shift(-widget.dayCount),
          onNavigateRight: () => _shift(widget.dayCount),
          onNavigateToday: () => setState(() => _baseDate = anchor),
          onWindowTap: (window) => logAction(
            context,
            'onWindowTap: ${window.placeCount} places open',
          ),
        ),
      ),
    );
  }
}
