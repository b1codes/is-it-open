import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../bloc/calendar/calendar_ui_state.dart';
import '../../bloc/calendar/calendar_ui_cubit.dart';
import '../../utils/calendar_dates.dart';
import '../../utils/places_theme.dart';

class CalendarHeaderWidget extends StatelessWidget {
  final CalendarViewType currentView;

  const CalendarHeaderWidget({super.key, required this.currentView});

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return SegmentedButton<CalendarViewType>(
      segments: [
        ButtonSegment(
          value: CalendarViewType.singleDay,
          label: Text(
            '1 Day',
            style: PlacesType.label(
              theme.ink,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ButtonSegment(
          value: CalendarViewType.threeDay,
          label: Text(
            '3 Days',
            style: PlacesType.label(
              theme.ink,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ButtonSegment(
          value: CalendarViewType.week,
          label: Text(
            'Week',
            style: PlacesType.label(
              theme.ink,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
      selected: <CalendarViewType>{currentView},
      onSelectionChanged: (Set<CalendarViewType> selection) {
        context.read<CalendarUiCubit>().changeViewType(selection.first);
      },
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.anchor.withValues(alpha: 0.1);
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.anchor;
          }
          return theme.ink;
        }),
        side: WidgetStateProperty.all(BorderSide(color: theme.ashSoft)),
      ),
    );
  }
}

String _formatHeaderDate(DateTime date) {
  return DateFormat('MMM d').format(date);
}

String buildCalendarHeaderText(
  CalendarViewType currentView,
  DateTime baseDate,
) {
  if (currentView == CalendarViewType.singleDay) {
    return DateFormat('EEEE, MMM d, yyyy').format(baseDate);
  } else if (currentView == CalendarViewType.threeDay) {
    final endDate = addCalendarDays(baseDate, 2);
    if (baseDate.month == endDate.month) {
      return '${_formatHeaderDate(baseDate)} – ${endDate.day}, ${DateFormat('yyyy').format(endDate)}';
    }
    return '${_formatHeaderDate(baseDate)} – ${_formatHeaderDate(endDate)}, ${DateFormat('yyyy').format(endDate)}';
  } else {
    final weekStart = addCalendarDays(baseDate, -(baseDate.weekday - 1));
    final weekEnd = addCalendarDays(weekStart, 6);
    if (weekStart.month == weekEnd.month) {
      return '${_formatHeaderDate(weekStart)} – ${weekEnd.day}, ${DateFormat('yyyy').format(weekEnd)}';
    }
    return '${_formatHeaderDate(weekStart)} – ${_formatHeaderDate(weekEnd)}, ${DateFormat('yyyy').format(weekEnd)}';
  }
}
