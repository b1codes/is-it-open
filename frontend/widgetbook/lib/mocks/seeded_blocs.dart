// Bloc.emit is @visibleForTesting. Seeding a starting state is the fixture
// use it exists for, and it lets these blocs keep their real event handlers
// running against FakeApiService instead of being inert mocks.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';

class SeededAuthBloc extends AuthBloc {
  SeededAuthBloc({required super.apiClient, required AuthState seed}) {
    emit(seed);
  }
}

class SeededCalendarDataBloc extends CalendarDataBloc {
  SeededCalendarDataBloc({
    required super.apiService,
    required super.icalParserService,
    required CalendarDataState seed,
  }) {
    emit(seed);
  }
}
