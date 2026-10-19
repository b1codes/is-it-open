import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/calendar/calendar_ui_cubit.dart';
import 'package:frontend/bloc/calendar/calendar_ui_state.dart';
import 'package:frontend/components/calendar/calendar_header.dart';

void main() {
  group('buildCalendarHeaderText', () {
    test('single day spells out the date', () {
      expect(
        buildCalendarHeaderText(
          CalendarViewType.singleDay,
          DateTime(2026, 10, 19),
        ),
        'Monday, Oct 19, 2026',
      );
    });

    test('three days within a month', () {
      expect(
        buildCalendarHeaderText(
          CalendarViewType.threeDay,
          DateTime(2026, 10, 19),
        ),
        'Oct 19 – 21, 2026',
      );
    });

    test('three days across months and years', () {
      expect(
        buildCalendarHeaderText(
          CalendarViewType.threeDay,
          DateTime(2026, 12, 30),
        ),
        'Dec 30 – Jan 1, 2027',
      );
    });

    test('a week starts on Monday', () {
      expect(
        buildCalendarHeaderText(CalendarViewType.week, DateTime(2026, 10, 22)),
        'Oct 19 – 25, 2026',
      );
      expect(
        buildCalendarHeaderText(CalendarViewType.week, DateTime(2026, 10, 25)),
        'Oct 19 – 25, 2026',
      );
    });

    test('a week across months', () {
      expect(
        buildCalendarHeaderText(CalendarViewType.week, DateTime(2026, 11, 1)),
        'Oct 26 – Nov 1, 2026',
      );
    });
  });

  testWidgets('the segmented control changes the view', (tester) async {
    final cubit = CalendarUiCubit(initialDate: DateTime(2026, 10, 19));
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: BlocBuilder<CalendarUiCubit, CalendarUiState>(
              builder: (_, state) =>
                  CalendarHeaderWidget(currentView: state.currentView),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1 Day'));
    await tester.pumpAndSettle();
    expect(cubit.state.currentView, CalendarViewType.singleDay);
    await tester.tap(find.text('3 Days'));
    await tester.pumpAndSettle();
    expect(cubit.state.currentView, CalendarViewType.threeDay);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(cubit.state.currentView, CalendarViewType.week);
  });
}
