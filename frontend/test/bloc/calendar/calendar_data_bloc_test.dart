import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_event.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/services/ical_parser_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import '../../helpers/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  group('CalendarDataBloc', () {
    late MockApiService mockApiService;
    late IcalParserService icalParserService;
    late CalendarDataBloc bloc;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApiService = MockApiService();
      icalParserService = IcalParserService();
      bloc = CalendarDataBloc(
        apiService: mockApiService,
        icalParserService: icalParserService,
      );
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is correct', () {
      expect(bloc.state.status, CalendarDataStatus.initial);
    });

    blocTest<CalendarDataBloc, CalendarDataState>(
      'LoadSavedPlaces emits [loading, loaded] when successful',
      build: () {
        when(() => mockApiService.getBookmarks()).thenAnswer((_) async => []);
        return bloc;
      },
      act: (bloc) => bloc.add(LoadSavedPlaces()),
      expect: () => [
        const CalendarDataState(status: CalendarDataStatus.loading),
        const CalendarDataState(
          status: CalendarDataStatus.loaded,
          savedPlaces: [],
        ),
      ],
    );

    blocTest<CalendarDataBloc, CalendarDataState>(
      'TogglePlaceFilter updates checkedPlaceIds',
      build: () => bloc,
      seed: () => const CalendarDataState(checkedPlaceIds: {'123'}),
      act: (bloc) => bloc.add(const TogglePlaceFilter('123')),
      expect: () => [const CalendarDataState(checkedPlaceIds: {})],
    );
  });
}
