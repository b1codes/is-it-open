import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/search/search_bloc.dart';
import 'package:frontend/bloc/search/search_event.dart';
import 'package:frontend/bloc/search/search_state.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/services/api_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';

Place _place(String id) => Place(
  tomtomId: id,
  name: 'Place $id',
  address: '$id Main St',
  location: const LatLng(0, 0),
);

Future<List<String>> _storedRecentIds() async {
  final prefs = await SharedPreferences.getInstance();
  return [
    for (final s in prefs.getStringList('recent_search_places') ?? <String>[])
      (jsonDecode(s) as Map<String, dynamic>)['tomtom_id'] as String,
  ];
}

void main() {
  late MockApiService api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = MockApiService();
  });

  SearchBloc build() => SearchBloc(apiClient: api);

  test('starts empty', () {
    expect(build().state, const SearchState());
  });

  group('SearchQueryChanged', () {
    blocTest<SearchBloc, SearchState>(
      'emits loading then the results',
      build: () {
        when(
          () => api.searchPlaces('coffee'),
        ).thenAnswer((_) async => [coffeePlace]);
        return build();
      },
      act: (bloc) => bloc.add(const SearchQueryChanged('coffee')),
      expect: () => [
        const SearchState(status: SearchStatus.loading),
        SearchState(status: SearchStatus.success, places: [coffeePlace]),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'an empty query resets the results without calling the API',
      build: build,
      seed: () =>
          SearchState(status: SearchStatus.success, places: [coffeePlace]),
      act: (bloc) => bloc.add(const SearchQueryChanged('')),
      expect: () => [const SearchState()],
      verify: (_) => verifyNever(() => api.searchPlaces(any())),
    );

    blocTest<SearchBloc, SearchState>(
      'reports a failed search',
      build: () {
        when(
          () => api.searchPlaces(any()),
        ).thenThrow(ApiException('Failed to search places: 500'));
        return build();
      },
      act: (bloc) => bloc.add(const SearchQueryChanged('x')),
      expect: () => [
        const SearchState(status: SearchStatus.loading),
        const SearchState(
          status: SearchStatus.failure,
          error: 'Exception: Failed to search places: 500',
        ),
      ],
    );

    test('a slow earlier response does not overwrite newer results', () async {
      final slow = Completer<List<Place>>();
      when(() => api.searchPlaces('cof')).thenAnswer((_) => slow.future);
      when(
        () => api.searchPlaces('coffee'),
      ).thenAnswer((_) async => [coffeePlace]);
      final bloc = build()
        ..add(const SearchQueryChanged('cof'))
        ..add(const SearchQueryChanged('coffee'));
      await pumpEventQueue();
      slow.complete([bistroPlace]);
      await pumpEventQueue();
      expect(bloc.state.places, [coffeePlace]);
      await bloc.close();
    });

    test('a response after the search is cleared is dropped', () async {
      final slow = Completer<List<Place>>();
      when(() => api.searchPlaces('coffee')).thenAnswer((_) => slow.future);
      final bloc = build()
        ..add(const SearchQueryChanged('coffee'))
        ..add(const SearchQueryChanged(''));
      await pumpEventQueue();
      slow.complete([coffeePlace]);
      await pumpEventQueue();
      expect(bloc.state, const SearchState());
      await bloc.close();
    });

    test('a stale failure does not replace newer results', () async {
      final slow = Completer<List<Place>>();
      when(() => api.searchPlaces('a')).thenAnswer((_) => slow.future);
      when(() => api.searchPlaces('ab')).thenAnswer((_) async => [gymPlace]);
      final bloc = build()
        ..add(const SearchQueryChanged('a'))
        ..add(const SearchQueryChanged('ab'));
      await pumpEventQueue();
      slow.completeError(ApiException('timeout'));
      await pumpEventQueue();
      expect(bloc.state.status, SearchStatus.success);
      expect(bloc.state.places, [gymPlace]);
      await bloc.close();
    });
  });

  group('LoadSearchSuggestions', () {
    blocTest<SearchBloc, SearchState>(
      'loads recent places from storage, then suggestions',
      setUp: () => SharedPreferences.setMockInitialValues({
        'recent_search_places': [jsonEncode(gymPlace.toJson())],
      }),
      build: () {
        when(
          () => api.getSuggestions(1.0, 2.0),
        ).thenAnswer((_) async => [coffeePlace]);
        return build();
      },
      act: (bloc) => bloc.add(const LoadSearchSuggestions(lat: 1, lng: 2)),
      expect: () => [
        SearchState(recentPlaces: [gymPlace]),
        SearchState(recentPlaces: [gymPlace], suggestions: [coffeePlace]),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'keeps the recent places when suggestions fail',
      build: () {
        when(
          () => api.getSuggestions(any(), any()),
        ).thenThrow(ApiException('down'));
        return build();
      },
      act: (bloc) => bloc.add(const LoadSearchSuggestions()),
      expect: () => [const SearchState()],
    );
  });

  group('AddRecentPlace', () {
    blocTest<SearchBloc, SearchState>(
      'puts the place first and persists it',
      build: build,
      act: (bloc) => bloc
        ..add(AddRecentPlace(coffeePlace))
        ..add(AddRecentPlace(gymPlace)),
      expect: () => [
        SearchState(recentPlaces: [coffeePlace]),
        SearchState(recentPlaces: [gymPlace, coffeePlace]),
      ],
      verify: (_) async {
        expect(await _storedRecentIds(), ['tt_gym', 'tt_coffee']);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'moves a repeated place to the top instead of duplicating it',
      build: build,
      act: (bloc) => bloc
        ..add(AddRecentPlace(coffeePlace))
        ..add(AddRecentPlace(gymPlace))
        ..add(AddRecentPlace(coffeePlace)),
      verify: (bloc) async {
        expect(bloc.state.recentPlaces, [coffeePlace, gymPlace]);
        expect(await _storedRecentIds(), ['tt_coffee', 'tt_gym']);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'keeps only the ten most recent',
      build: build,
      act: (bloc) {
        for (var i = 0; i < 12; i++) {
          bloc.add(AddRecentPlace(_place('p$i')));
        }
      },
      verify: (bloc) async {
        final ids = await _storedRecentIds();
        expect(ids, [for (var i = 11; i >= 2; i--) 'p$i']);
        expect(bloc.state.recentPlaces.map((p) => p.tomtomId), ids);
      },
    );
  });

  test('events compare by value', () {
    expect(const SearchQueryChanged('a'), const SearchQueryChanged('a'));
    expect(const LoadSearchSuggestions().props, [0.0, 0.0]);
    expect(const LoadSearchSuggestions(lat: 1, lng: 2).props, [1.0, 2.0]);
    expect(AddRecentPlace(coffeePlace).props, [coffeePlace]);
  });
}
