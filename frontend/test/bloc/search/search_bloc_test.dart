import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:frontend/bloc/search/search_bloc.dart';
import 'package:frontend/bloc/search/search_event.dart';
import 'package:frontend/bloc/search/search_state.dart';
import 'package:frontend/models/place.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchBloc', () {
    late MockApiService mockApiService;
    late SearchBloc bloc;

    final mockPlace = Place(
      tomtomId: '123',
      name: 'Test Place',
      address: '123 Test St',
      location: const LatLng(0, 0),
      categories: const ['Test'],
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApiService = MockApiService();
      bloc = SearchBloc(apiClient: mockApiService);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is correct', () {
      expect(bloc.state.status, SearchStatus.initial);
      expect(bloc.state.places, isEmpty);
      expect(bloc.state.suggestions, isEmpty);
      expect(bloc.state.recentPlaces, isEmpty);
    });

    blocTest<SearchBloc, SearchState>(
      'SearchQueryChanged emits [loading, success] when successful',
      build: () {
        when(
          () => mockApiService.searchPlaces('test'),
        ).thenAnswer((_) async => [mockPlace]);
        return bloc;
      },
      act: (bloc) => bloc.add(const SearchQueryChanged('test')),
      expect: () => [
        const SearchState(status: SearchStatus.loading),
        SearchState(status: SearchStatus.success, places: [mockPlace]),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'LoadSearchSuggestions loads recent places and fetches suggestions',
      build: () {
        when(
          () => mockApiService.getSuggestions(any(), any()),
        ).thenAnswer((_) async => [mockPlace]);
        return bloc;
      },
      act: (bloc) => bloc.add(const LoadSearchSuggestions(lat: 1.0, lng: 1.0)),
      expect: () => [
        const SearchState(
          recentPlaces: [],
        ), // Emitted by loading from prefs (empty initially)
        SearchState(recentPlaces: const [], suggestions: [mockPlace]),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'AddRecentPlace saves place to shared preferences and updates state',
      build: () => bloc,
      act: (bloc) => bloc.add(AddRecentPlace(mockPlace)),
      expect: () => [
        SearchState(recentPlaces: [mockPlace]),
      ],
      verify: (_) async {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('recent_search_places'), isNotEmpty);
      },
    );
  });
}
