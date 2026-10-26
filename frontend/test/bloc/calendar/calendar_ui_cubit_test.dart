import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:frontend/bloc/calendar/calendar_ui_cubit.dart';
import 'package:frontend/bloc/calendar/calendar_ui_state.dart'
    show CalendarViewType, CalendarUiState;

void main() {
  group('CalendarUiCubit', () {
    late CalendarUiCubit cubit;
    late DateTime now;

    setUp(() {
      now = DateTime.now();
      cubit = CalendarUiCubit(initialDate: now);
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state is correct', () {
      expect(cubit.state.currentView, CalendarViewType.week);
      expect(cubit.state.baseDate, now);
      expect(cubit.state.isCalendarExpanded, false);
      expect(cubit.state.isCalendarMinimized, false);
    });

    blocTest<CalendarUiCubit, CalendarUiState>(
      'emits new state when changeViewType is called',
      build: () => cubit,
      act: (cubit) {
        // Mock DateTime.now inside the cubit action or test it carefully.
        // changeViewType resets baseDate to DateTime.now() in the cubit.
        cubit.changeViewType(CalendarViewType.singleDay);
      },
      // Since DateTime.now() is called inside changeViewType, we only check the view and expanded states
      verify: (cubit) {
        expect(cubit.state.currentView, CalendarViewType.singleDay);
        expect(cubit.state.isCalendarExpanded, false);
        expect(cubit.state.isCalendarMinimized, false);
      },
    );

    blocTest<CalendarUiCubit, CalendarUiState>(
      'emits new state when navigateDate is called',
      build: () => cubit,
      act: (cubit) => cubit.navigateDate(now.add(const Duration(days: 1))),
      expect: () => [
        CalendarUiState(
          currentView: CalendarViewType.week,
          baseDate: now.add(const Duration(days: 1)),
          isCalendarExpanded: false,
          isCalendarMinimized: false,
        ),
      ],
    );

    blocTest<CalendarUiCubit, CalendarUiState>(
      'emits new state when toggleExpanded is called',
      build: () => cubit,
      act: (cubit) => cubit.toggleExpanded(),
      expect: () => [
        CalendarUiState(
          currentView: CalendarViewType.week,
          baseDate: now,
          isCalendarExpanded: true,
          isCalendarMinimized: false,
        ),
      ],
    );

    blocTest<CalendarUiCubit, CalendarUiState>(
      'emits new state when toggleMinimized is called',
      build: () => cubit,
      act: (cubit) => cubit.toggleMinimized(),
      expect: () => [
        CalendarUiState(
          currentView: CalendarViewType.week,
          baseDate: now,
          isCalendarExpanded: false,
          isCalendarMinimized: true,
        ),
      ],
    );

    blocTest<CalendarUiCubit, CalendarUiState>(
      'toggles the sidebar, business hours and personal events',
      build: () => cubit,
      act: (cubit) => cubit
        ..toggleSidebar()
        ..toggleBusinessHours()
        ..togglePersonalEvents()
        ..toggleSidebar(),
      verify: (cubit) {
        expect(cubit.state.isSidebarCollapsed, isFalse);
        expect(cubit.state.showBusinessHours, isFalse);
        expect(cubit.state.showPersonalEvents, isFalse);
      },
    );
  });
}
