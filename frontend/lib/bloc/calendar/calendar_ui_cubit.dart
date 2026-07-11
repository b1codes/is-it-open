import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timezone/timezone.dart' as tz;
import 'calendar_ui_state.dart';

class CalendarUiCubit extends Cubit<CalendarUiState> {
  CalendarUiCubit({DateTime? initialDate, bool initialSidebarCollapsed = false})
    : super(
        CalendarUiState(
          currentView: CalendarViewType.week,
          baseDate: initialDate ?? tz.TZDateTime.now(tz.local),
          isCalendarExpanded: false,
          isCalendarMinimized: false,
          isSidebarCollapsed: initialSidebarCollapsed,
          showBusinessHours: true,
          showPersonalEvents: true,
        ),
      );

  void changeViewType(CalendarViewType type) {
    emit(state.copyWith(currentView: type));
  }

  void navigateDate(DateTime newDate) {
    emit(state.copyWith(baseDate: newDate));
  }

  void toggleExpanded() {
    emit(
      state.copyWith(
        isCalendarExpanded: !state.isCalendarExpanded,
        isCalendarMinimized: false,
      ),
    );
  }

  void toggleMinimized() {
    emit(
      state.copyWith(
        isCalendarMinimized: !state.isCalendarMinimized,
        isCalendarExpanded: false,
      ),
    );
  }

  void toggleSidebar() {
    emit(state.copyWith(isSidebarCollapsed: !state.isSidebarCollapsed));
  }

  void toggleBusinessHours() {
    emit(state.copyWith(showBusinessHours: !state.showBusinessHours));
  }

  void togglePersonalEvents() {
    emit(state.copyWith(showPersonalEvents: !state.showPersonalEvents));
  }
}
