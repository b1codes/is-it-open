import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_ui_cubit.dart';
import 'package:frontend/bloc/calendar/calendar_ui_state.dart';
import 'package:frontend/components/calendar/calendar_header.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/stage.dart';

@widgetbook.UseCase(name: 'Default', type: CalendarHeaderWidget)
Widget buildCalendarHeaderUseCase(BuildContext context) {
  final initialView = context.knobs.object.segmented<CalendarViewType>(
    label: 'Initial view',
    options: CalendarViewType.values,
    initialOption: CalendarViewType.week,
    labelBuilder: (view) => view.name,
  );
  // The header writes the selection back to CalendarUiCubit; reading it
  // back here keeps the segmented control interactive.
  return BlocProvider(
    key: ValueKey(initialView),
    create: (_) => CalendarUiCubit()..changeViewType(initialView),
    child: ComponentStage(
      maxWidth: 720,
      child: BlocBuilder<CalendarUiCubit, CalendarUiState>(
        builder: (context, state) =>
            CalendarHeaderWidget(currentView: state.currentView),
      ),
    ),
  );
}
