import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/today/today_cubit.dart';
import 'package:frontend/components/places/quick_add_place_sheet.dart';
import 'package:frontend/components/places/saved_place_row.dart';
import 'package:frontend/components/places/saved_place_tile.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/graphics_helper.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

// Monday 19 Oct 2026, noon: coffee, bistro and the gym are open, the
// library closes for lunch at 12:30, and the hardware store has no hours.
final _noon = DateTime(2026, 10, 19, 12);

List<String> _rowNames(WidgetTester tester) => [
  for (final row in tester.widgetList<SavedPlaceRow>(
    find.byType(SavedPlaceRow),
  ))
    row.savedPlace.customName ?? row.savedPlace.place.name,
];

void main() {
  setUpAll(registerFallbacks);

  Future<void> pump(
    WidgetTester tester, {
    List<SavedPlace>? bookmarks,
    List<String> todayRouteIds = const [],
    bool apiFails = false,
    ApiService? api,
  }) async {
    await tester.pumpApp(
      const MyPlacesScreen(),
      bookmarks: bookmarks,
      todayRouteIds: todayRouteIds,
      apiFails: apiFails,
      api: api,
      size: const Size(600, 2000),
    );
    await tester.pumpAndSettle();
  }

  TodayRouteCubit today(WidgetTester tester) =>
      tester.element(find.byType(MyPlacesScreen)).read<TodayRouteCubit>();

  testWidgets('groups places by status, pinned first', (tester) async {
    await withClock(Clock.fixed(_noon), () async {
      await pump(tester);
      expect(find.text('OPEN NOW'), findsOneWidget);
      expect(find.text('CLOSES SOON'), findsOneWidget);
      expect(find.text('HOURS UNKNOWN'), findsOneWidget);
      expect(find.text('CLOSED'), findsNothing);
      expect(_rowNames(tester), [
        // Open: pinned (coffee, bistro), then by closing time.
        coffeePlace.name,
        'Friday burger spot',
        gymPlace.name,
        libraryPlace.name, // closes soon
        hardwarePlace.name, // unknown
      ]);
      await tester.unmount();
    });
  });

  testWidgets('filters by want-to-visit and visited, with counts', (
    tester,
  ) async {
    await withClock(Clock.fixed(_noon), () async {
      await pump(tester);
      await tester.tap(find.text('Want to visit'));
      await tester.pumpAndSettle();
      expect(_rowNames(tester), [libraryPlace.name, hardwarePlace.name]);
      await tester.tap(find.text('Visited'));
      await tester.pumpAndSettle();
      expect(_rowNames(tester), hasLength(3));
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(_rowNames(tester), hasLength(5));
      await tester.unmount();
    });
  });

  testWidgets('a place keeps its map color whatever the filter and grouping', (
    tester,
  ) async {
    await withClock(Clock.fixed(_noon), () async {
      // Without stored colors, each place takes the palette slot for its
      // position among all saved places, as on the map and calendar.
      final uncolored = [
        for (final sp in sampleSavedPlaces)
          SavedPlace(
            id: sp.id,
            place: sp.place,
            customName: sp.customName,
            icon: sp.icon,
            isPinned: sp.isPinned,
            isCheckItOut: sp.isCheckItOut,
          ),
      ];
      await pump(tester, bookmarks: uncolored);
      await tester.tap(find.text('Want to visit'));
      await tester.pumpAndSettle();
      Color? graphicColor(IconData icon) =>
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: find.byIcon(icon),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      // The library (a star) and the hardware store, fourth and fifth.
      expect(graphicColor(Icons.star), GraphicsHelper.defaultPalette[3]);
      expect(graphicColor(Icons.store), GraphicsHelper.defaultPalette[4]);
      await tester.unmount();
    });
  });

  testWidgets('switches between list and grid', (tester) async {
    await withClock(Clock.fixed(_noon), () async {
      await pump(tester);
      await tester.tap(find.byTooltip('Grid view'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedPlaceTile), findsWidgets);
      expect(find.byType(SavedPlaceRow), findsNothing);
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedPlaceRow), findsWidgets);
      await tester.unmount();
    });
  });

  testWidgets('tapping a place opens its details', (tester) async {
    await withClock(Clock.fixed(_noon), () async {
      await pump(tester);
      await tester.tap(find.text(gymPlace.name));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailScreen), findsNothing);
      await tester.unmount();
    });
  });

  // The list reloads when a place's details close. If it had gone in the
  // meantime (the home screen switching layout on rotation, say), the reload
  // used its defunct context and threw (found by the monkey test).
  testWidgets('closing details after the list has gone is harmless', (
    tester,
  ) async {
    await withClock(Clock.fixed(_noon), () async {
      final showList = ValueNotifier(true);
      await tester.pumpApp(
        ValueListenableBuilder<bool>(
          valueListenable: showList,
          builder: (_, show, _) =>
              show ? const MyPlacesScreen() : const SizedBox.shrink(),
        ),
        size: const Size(600, 2000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(gymPlace.name));
      await tester.pumpAndSettle();

      showList.value = false;
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(PlaceDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });
  });

  group("today's route", () {
    testWidgets('adding a place shows it as a numbered stop', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester);
        expect(find.text("Nothing on today's plan yet."), findsOneWidget);
        final gymRow = find.ancestor(
          of: find.text(gymPlace.name),
          matching: find.byType(SavedPlaceRow),
        );
        await tester.tap(
          find.descendant(of: gymRow, matching: find.text('Today')),
        );
        await tester.pumpAndSettle();
        expect(today(tester).state.tomtomIds, ['tt_gym']);
        expect(
          find.bySemanticsLabel(RegExp('Route stop: ${gymPlace.name}')),
          findsOneWidget,
        );
        await tester.unmount();
      });
    });

    testWidgets('stops can be reordered and removed', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester, todayRouteIds: ['tt_coffee', 'tt_gym']);
        await tester.longPress(
          find.bySemanticsLabel(RegExp('Route stop: ${coffeePlace.name}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Move earlier'), findsNothing);
        await tester.tap(find.text('Move later'));
        await tester.pumpAndSettle();
        expect(today(tester).state.tomtomIds, ['tt_gym', 'tt_coffee']);

        await tester.longPress(
          find.bySemanticsLabel(RegExp('Route stop: ${coffeePlace.name}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Move earlier'));
        await tester.pumpAndSettle();
        expect(today(tester).state.tomtomIds, ['tt_coffee', 'tt_gym']);

        await tester.longPress(
          find.bySemanticsLabel(RegExp('Route stop: ${gymPlace.name}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from today'));
        await tester.pumpAndSettle();
        expect(today(tester).state.tomtomIds, ['tt_coffee']);
        await tester.unmount();
      });
    });

    testWidgets('stops come from the loaded list, without refetching', (
      tester,
    ) async {
      await withClock(Clock.fixed(_noon), () async {
        final api = MockApiService();
        when(
          () => api.getBookmarks(),
        ).thenAnswer((_) async => sampleSavedPlaces);
        await pump(tester, api: api, todayRouteIds: ['tt_coffee', 'tt_gym']);
        expect(
          find.bySemanticsLabel(RegExp('Route stop: ${gymPlace.name}')),
          findsOneWidget,
        );
        // Rebuilds (here, a route change) don't refetch for the stops.
        await today(tester).reorder(0, 2);
        await tester.pumpAndSettle();
        verify(() => api.getBookmarks()).called(1);
        await tester.unmount();
      });
    });

    testWidgets('a stop that is no longer saved says so', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester, todayRouteIds: ['tt_gone']);
        expect(find.text('Not in your places'), findsOneWidget);
        await tester.unmount();
      });
    });

    testWidgets('notes an overnight reset until dismissed', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester);
        await today(tester).add('tt_gym');
        await withClock(
          Clock.fixed(_noon.add(const Duration(days: 1))),
          () async {
            await today(tester).refresh();
            await tester.pumpAndSettle();
            expect(
              find.text("Today's route reset for Tue, Oct 20."),
              findsOneWidget,
            );
            await tester.tap(find.text("Today's route reset for Tue, Oct 20."));
            await tester.pumpAndSettle();
            expect(find.textContaining("route reset"), findsNothing);
          },
        );
        await tester.unmount();
      });
    });
  });

  group('actions', () {
    Future<void> openActions(WidgetTester tester, String name) async {
      await tester.longPress(
        find.descendant(
          of: find.byType(SavedPlaceRow),
          matching: find.text(name),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('pin moves a place to the top of its group', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester);
        await openActions(tester, gymPlace.name);
        await tester.tap(find.text('Pin'));
        await tester.pumpAndSettle();
        // Pinned places lead, ordered by closing time: coffee 6pm, gym 10pm,
        // the bistro 11pm.
        expect(_rowNames(tester).take(3), [
          coffeePlace.name,
          gymPlace.name,
          'Friday burger spot',
        ]);

        await openActions(tester, gymPlace.name);
        expect(find.text('Unpin'), findsOneWidget);
        await tester.tap(find.text('Unpin'));
        await tester.pumpAndSettle();
        expect(_rowNames(tester)[2], gymPlace.name);
        await tester.unmount();
      });
    });

    testWidgets('moving to want-to-visit updates the filters', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester);
        await openActions(tester, gymPlace.name);
        await tester.tap(find.text('Move to want to visit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Want to visit'));
        await tester.pumpAndSettle();
        expect(_rowNames(tester), contains(gymPlace.name));

        await openActions(tester, gymPlace.name);
        await tester.tap(find.text('Mark as visited'));
        await tester.pumpAndSettle();
        expect(_rowNames(tester), isNot(contains(gymPlace.name)));
        await tester.unmount();
      });
    });

    testWidgets('edit details opens the place', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester);
        await openActions(tester, gymPlace.name);
        await tester.tap(find.text('Edit details'));
        await tester.pumpAndSettle();
        expect(find.byType(PlaceDetailScreen), findsOneWidget);
        await tester.unmount();
      });
    });

    testWidgets('remove deletes the place and its route stop', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester, todayRouteIds: ['tt_gym']);
        await openActions(tester, gymPlace.name);
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(_rowNames(tester), isNot(contains(gymPlace.name)));
        expect(today(tester).state.tomtomIds, isEmpty);
        await tester.unmount();
      });
    });

    testWidgets('a failed action says so', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        final api = MockApiService();
        when(
          () => api.getBookmarks(),
        ).thenAnswer((_) async => sampleSavedPlaces);
        when(
          () => api.togglePinPlace(any(), any()),
        ).thenThrow(ApiException('down'));
        when(
          () => api.toggleCheckItOut(any(), any()),
        ).thenThrow(ApiException('down'));
        when(() => api.deleteBookmark(any())).thenThrow(ApiException('down'));
        await pump(tester, api: api);
        for (final (action, message) in [
          ('Pin', "Couldn't pin ${gymPlace.name}."),
          ('Move to want to visit', "Couldn't update ${gymPlace.name}."),
          ('Remove', "Couldn't remove ${gymPlace.name}."),
        ]) {
          await openActions(tester, gymPlace.name);
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          expect(find.text(message), findsOneWidget, reason: action);
          ScaffoldMessenger.of(
            tester.element(find.byType(MyPlacesScreen)),
          ).removeCurrentSnackBar();
          await tester.pumpAndSettle();
        }
        await tester.unmount();
      });
    });
  });

  group('states', () {
    testWidgets('shows a skeleton while loading', (tester) async {
      await tester.pumpApp(const MyPlacesScreen(), apiLatency: null);
      await tester.pump();
      expect(find.byType(SavedPlaceRow), findsNothing);
      expect(find.text('A pocket of places.'), findsNothing);
      await tester.unmount();
    });

    testWidgets('an error can be retried', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        final api = MockApiService();
        var calls = 0;
        when(() => api.getBookmarks()).thenAnswer((_) async {
          if (calls++ == 0) throw ApiException('down');
          return sampleSavedPlaces;
        });
        await pump(tester, api: api);
        expect(find.text("Couldn't load your places."), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.byType(SavedPlaceRow), findsNWidgets(5));
        await tester.unmount();
      });
    });

    testWidgets('the refresh button reloads', (tester) async {
      await withClock(Clock.fixed(_noon), () async {
        final api = MockApiService();
        when(
          () => api.getBookmarks(),
        ).thenAnswer((_) async => sampleSavedPlaces);
        await pump(tester, api: api);
        await tester.tap(find.byTooltip('Refresh'));
        await tester.pumpAndSettle();
        verify(() => api.getBookmarks()).called(2);
        await tester.unmount();
      });
    });

    testWidgets('the empty state points to search and quick add', (
      tester,
    ) async {
      await withClock(Clock.fixed(_noon), () async {
        await pump(tester, bookmarks: const []);
        expect(find.text('A pocket of places.'), findsOneWidget);
        await tester.tap(find.text('Find a place'));
        await tester.pumpAndSettle();
        expect(
          find.text('Use Search from the menu to find places.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Add a custom place'));
        await tester.pumpAndSettle();
        expect(find.byType(QuickAddPlaceSheet), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'),
          'Trailhead',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Address'),
          '1 Forest Rd',
        );
        await tester.tap(find.text('Save place'));
        await tester.pumpAndSettle();
        // The new place replaces the empty state without a manual refresh.
        expect(find.text('A pocket of places.'), findsNothing);
        expect(find.byType(SavedPlaceRow), findsOneWidget);
        await tester.unmount();
      });
    });
  });

  testWidgets('embedded, it has no app bar', (tester) async {
    await withClock(Clock.fixed(_noon), () async {
      await tester.pumpApp(
        const Scaffold(body: MyPlacesScreen(embedded: true)),
        size: const Size(600, 1600),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Refresh'), findsNothing);
      expect(find.byType(SavedPlaceRow), findsNWidgets(5));
      await tester.unmount();
    });
  });
}
