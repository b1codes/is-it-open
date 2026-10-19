import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/search/search_result_grid_card.dart';
import 'package:frontend/components/search/search_result_list_card.dart';
import 'package:frontend/screens/places/create_place_screen.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/app_theme.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Only an ApiService above the screen, as in the real app: no app-level
  // SearchBloc that could stand in for the screen's own.
  Future<void> pump(WidgetTester tester, ApiService api) async {
    tester.setViewport(phoneSize);
    await tester.pumpWidget(
      RepositoryProvider<ApiService>.value(
        value: api,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  group('suggestions', () {
    testWidgets('load with the current location', (tester) async {
      FakeGeolocator.install(
        addTearDown,
        FakeGeolocator(position: fakePosition(40.7, -74.0)),
      );
      final api = MockApiService();
      when(
        () => api.getSuggestions(any(), any()),
      ).thenAnswer((_) async => [coffeePlace, gymPlace]);

      await pump(tester, api);
      expect(find.text('Trending Nearby'), findsOneWidget);
      expect(find.text(coffeePlace.name), findsOneWidget);
      verify(() => api.getSuggestions(40.7, -74.0)).called(1);
    });

    testWidgets('load without a location when permission is denied', (
      tester,
    ) async {
      FakeGeolocator.install(
        addTearDown,
        FakeGeolocator(permission: LocationPermission.denied),
      );
      final api = MockApiService();
      when(
        () => api.getSuggestions(any(), any()),
      ).thenAnswer((_) async => [coffeePlace]);
      await pump(tester, api);
      verify(() => api.getSuggestions(null, null)).called(1);
      expect(find.byType(SearchResultGridCard), findsOneWidget);
    });

    testWidgets('show recent searches from storage', (tester) async {
      SharedPreferences.setMockInitialValues({
        'recent_search_places': [jsonEncode(libraryPlace.toJson())],
      });
      FakeGeolocator.install(addTearDown);
      await pump(tester, FakeApiService(latency: Duration.zero));
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text(libraryPlace.name), findsWidgets);
    });

    testWidgets('explain when there is nothing to suggest', (tester) async {
      FakeGeolocator.install(addTearDown);
      final api = MockApiService();
      when(() => api.getSuggestions(any(), any())).thenAnswer((_) async => []);
      await pump(tester, api);
      expect(
        find.text('No suggestions available.\nTry searching for something!'),
        findsOneWidget,
      );
    });
  });

  group('searching', () {
    testWidgets('lists results, switches to a grid, and clears', (
      tester,
    ) async {
      FakeGeolocator.install(addTearDown);
      await pump(tester, FakeApiService(latency: Duration.zero));
      await search(tester, 'coffee');
      expect(find.byType(SearchResultListCard), findsOneWidget);
      expect(find.text("Don't see it? Create a New Place"), findsOneWidget);

      await tester.tap(find.byTooltip('Grid View'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchResultGridCard), findsOneWidget);
      expect(find.text("Don't see it?\nCreate a New Place"), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Trending Nearby'), findsOneWidget);
    });

    testWidgets('the Search button runs the query', (tester) async {
      FakeGeolocator.install(addTearDown);
      await pump(tester, FakeApiService(latency: Duration.zero));
      await tester.enterText(find.byType(TextField), 'gym');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
      await tester.pumpAndSettle();
      expect(find.text(gymPlace.name), findsOneWidget);
    });

    testWidgets('an empty query does nothing', (tester) async {
      FakeGeolocator.install(addTearDown);
      final api = MockApiService();
      when(() => api.getSuggestions(any(), any())).thenAnswer((_) async => []);
      await pump(tester, api);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
      await tester.pumpAndSettle();
      verifyNever(() => api.searchPlaces(any()));
    });

    testWidgets('offers to create a place when nothing matches', (
      tester,
    ) async {
      FakeGeolocator.install(addTearDown);
      await pump(tester, FakeApiService(latency: Duration.zero));
      await search(tester, 'zzz no such place');
      expect(find.text('No results found'), findsOneWidget);
      await tester.tap(find.text('Create a New Place'));
      await tester.pumpAndSettle();
      expect(find.byType(CreatePlaceScreen), findsOneWidget);
    });

    testWidgets('shows a failed search', (tester) async {
      FakeGeolocator.install(addTearDown);
      final api = MockApiService();
      when(() => api.getSuggestions(any(), any())).thenAnswer((_) async => []);
      when(
        () => api.searchPlaces(any()),
      ).thenThrow(ApiException('Failed to search places: 500'));
      await pump(tester, api);
      await search(tester, 'coffee');
      expect(
        find.text('Error: Exception: Failed to search places: 500'),
        findsOneWidget,
      );
    });

    testWidgets('clearing the field reloads suggestions', (tester) async {
      FakeGeolocator.install(addTearDown);
      final api = MockApiService();
      when(() => api.getSuggestions(any(), any())).thenAnswer((_) async => []);
      when(
        () => api.searchPlaces(any()),
      ).thenAnswer((_) async => [coffeePlace]);
      await pump(tester, api);
      await search(tester, 'coffee');
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      verify(() => api.getSuggestions(any(), any())).called(2);
      expect(find.byType(SearchResultListCard), findsNothing);
    });
  });
}
