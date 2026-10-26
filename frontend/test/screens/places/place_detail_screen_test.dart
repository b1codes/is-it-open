import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/today/today_cubit.dart';
import 'package:frontend/components/places/address_map_thumb.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';
import 'package:frontend/screens/places/plan_visit_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/graphics_helper.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/pump_app.dart';

void main() {
  setUpAll(registerFallbacks);

  group('PlaceDetailScreen', () {
    // Today's row in the hours table gets a dot and a bold label; on some
    // weekdays that overflowed its fixed-width label column.
    for (var day = 0; day < 7; day++) {
      final date = DateTime(2026, 10, 19 + day, 12); // Mon 19 Oct .. Sun 25 Oct
      testWidgets('lays out the hours table with ${_weekday(date)} as today', (
        tester,
      ) async {
        await withClock(Clock.fixed(date), () async {
          await tester.pumpApp(PlaceDetailScreen(place: coffeePlace));
          await tester.pumpAndSettle();
          expect(find.text('Hours'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.unmount();
        });
      });
    }

    // Monday 19 Oct 2026, noon.
    final noon = DateTime(2026, 10, 19, 12);

    // The today's-route button had a fixed height and a label that couldn't
    // wrap; on a 320-wide phone (the Android emulator's default) at 2× text
    // it overflowed (found by the monkey test on a device).
    for (final onToday in [false, true]) {
      testWidgets(
        'the ${onToday ? 'on' : 'add to'} today button fits a small phone '
        'at 2× text',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await withClock(Clock.fixed(noon), () async {
            await tester.pumpApp(
              PlaceDetailScreen(place: hardwarePlace),
              size: const Size(320, 640),
              todayRouteIds: onToday ? const ['custom_hardware'] : const [],
            );
            await tester.pumpAndSettle();
            expect(
              find.text(onToday ? "On today's route" : "Add to today's route"),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.unmount();
          });
        },
      );
    }

    Future<void> open(
      WidgetTester tester,
      Place place, {
      List<SavedPlace>? bookmarks,
      bool apiFails = false,
      List<String> todayRouteIds = const [],
      ApiService? api,
    }) async {
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaceDetailScreen(place: place),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        bookmarks: bookmarks,
        apiFails: apiFails,
        todayRouteIds: todayRouteIds,
        api: api,
        size: const Size(600, 1400),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a saved place with its details', (tester) async {
      await withClock(Clock.fixed(noon), () async {
        await open(tester, bistroPlace);
        expect(find.text('Friday burger spot'), findsOneWidget);
        expect(find.text('restaurant'), findsOneWidget);
        expect(find.text(bistroPlace.address), findsOneWidget);
        expect(find.byType(AddressMapThumb), findsOneWidget);
        expect(find.text('Contact'), findsOneWidget);
        expect(find.text(bistroPlace.phone!), findsOneWidget);
        expect(find.text('Plan visit'), findsOneWidget);
        expect(
          find.text('Typical visit 1.5 hr. Check if it fits.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
      });
    });

    testWidgets('a saved place without a color shows its map color', (
      tester,
    ) async {
      await withClock(Clock.fixed(noon), () async {
        // The palette slot for its position among the saved places, as on
        // the map and calendar.
        final library = sampleSavedPlaces[3];
        await open(
          tester,
          libraryPlace,
          bookmarks: [
            ...sampleSavedPlaces.take(3),
            SavedPlace(id: library.id, place: library.place, icon: 'park'),
          ],
        );
        final circle =
            tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: find.byIcon(Icons.park),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(circle.color, GraphicsHelper.defaultPalette[3]);
      });
    });

    testWidgets('an unsaved place has no saved-place actions', (tester) async {
      await withClock(Clock.fixed(noon), () async {
        await open(tester, bistroPlace, bookmarks: const []);
        expect(find.text(bistroPlace.name), findsOneWidget);
        expect(find.text('Plan visit'), findsNothing);
        expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      });
    });

    testWidgets('adding to today saves and bookmarks an unsaved place', (
      tester,
    ) async {
      await withClock(Clock.fixed(noon), () async {
        await open(tester, gymPlace, bookmarks: const []);
        await tester.tap(find.text("Add to today's route"));
        await tester.pumpAndSettle();
        expect(find.text("On today's route"), findsOneWidget);
        expect(find.text('Plan visit'), findsOneWidget, reason: 'now saved');
        final context = tester.element(find.byType(PlaceDetailScreen));
        expect(context.read<TodayRouteCubit>().state.tomtomIds, ['tt_gym']);

        await tester.tap(find.text("On today's route"));
        await tester.pumpAndSettle();
        expect(context.read<TodayRouteCubit>().state.tomtomIds, isEmpty);
      });
    });

    testWidgets('explains a failed add', (tester) async {
      await withClock(Clock.fixed(noon), () async {
        final api = MockApiService();
        when(() => api.getBookmarks()).thenAnswer((_) async => []);
        when(() => api.savePlace(any())).thenThrow(ApiException('down'));
        await open(tester, gymPlace, api: api);
        await tester.tap(find.text("Add to today's route"));
        await tester.pumpAndSettle();
        expect(find.text("Couldn't add to today."), findsOneWidget);
        expect(find.text("Add to today's route"), findsOneWidget);
      });
    });

    // A failed add that finished after the user left used to show its
    // SnackBar and set state on the closed screen (found by the monkey test).
    testWidgets('an add that fails after going back is dropped', (
      tester,
    ) async {
      await withClock(Clock.fixed(noon), () async {
        final api = MockApiService();
        final saved = Completer<Place>();
        when(() => api.getBookmarks()).thenAnswer((_) async => []);
        when(() => api.savePlace(any())).thenAnswer((_) => saved.future);
        await open(tester, gymPlace, api: api);
        await tester.tap(find.text("Add to today's route"));
        await tester.pump();

        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        saved.completeError(ApiException('down'));
        await tester.pumpAndSettle();

        expect(find.byType(PlaceDetailScreen), findsNothing);
        expect(find.text("Couldn't add to today."), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a bookmarks failure still shows the place', (tester) async {
      await withClock(Clock.fixed(noon), () async {
        await open(tester, coffeePlace, apiFails: true);
        expect(find.text(coffeePlace.name), findsOneWidget);
        expect(find.text("Add to today's route"), findsOneWidget);
      });
    });

    testWidgets('remove from saved deletes it and goes back', (tester) async {
      await withClock(Clock.fixed(noon), () async {
        await open(tester, coffeePlace, todayRouteIds: const ['tt_coffee']);
        final context = tester.element(find.byType(PlaceDetailScreen));
        final today = context.read<TodayRouteCubit>();
        final api = context.read<ApiService>();
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from saved'));
        await tester.pumpAndSettle();
        expect(find.byType(PlaceDetailScreen), findsNothing);
        expect(today.state.tomtomIds, isEmpty);
        final remaining = (await tester.runAsync(api.getBookmarks))!;
        expect(
          remaining.map((b) => b.place.tomtomId),
          isNot(contains('tt_coffee')),
        );
      });
    });

    // Leaving while the removal was in flight used to pop again once it
    // finished, closing the screen underneath and leaving the navigator
    // empty (found by the monkey test).
    testWidgets('going back during a removal closes only this screen', (
      tester,
    ) async {
      await withClock(Clock.fixed(noon), () async {
        final api = MockApiService();
        final deleted = Completer<void>();
        when(
          () => api.getBookmarks(),
        ).thenAnswer((_) async => [SavedPlace(id: 1, place: coffeePlace)]);
        when(() => api.deleteBookmark(any())).thenAnswer((_) => deleted.future);
        await open(tester, coffeePlace, api: api);
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from saved'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pump(const Duration(milliseconds: 100)); // mid-transition
        deleted.complete();
        await tester.pumpAndSettle();

        expect(find.byType(PlaceDetailScreen), findsNothing);
        expect(find.text('open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('opens plan visit and refreshes on return', (tester) async {
      await withClock(Clock.fixed(noon), () async {
        await open(tester, gymPlace);
        await tester.tap(find.text('Plan visit'));
        await tester.pumpAndSettle();
        expect(find.byType(PlanVisitScreen), findsOneWidget);
        await tester.tap(find.text('2 hr'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(
          find.text('Typical visit 2 hr. Check if it fits.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('a custom place without hours offers to add them', (
      tester,
    ) async {
      await withClock(Clock.fixed(noon), () async {
        await open(tester, hardwarePlace);
        expect(find.text('Hours unknown'), findsOneWidget);
        await tester.tap(find.text('Add hours'));
        await tester.pumpAndSettle();
        expect(find.text('Edit hours'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Edit hours'), findsNothing);
      });
    });

    testWidgets('a saved custom place can be relabelled or cleared', (
      tester,
    ) async {
      await withClock(Clock.fixed(noon), () async {
        await open(tester, hardwarePlace);
        final label = find.widgetWithText(TextField, hardwarePlace.name);
        await tester.ensureVisible(label);
        await tester.enterText(label, 'The hardware store');
        await tester.tap(find.text('Save label'));
        await tester.pumpAndSettle();
        expect(find.text('The hardware store'), findsWidgets);

        await tester.enterText(
          find.widgetWithText(TextField, 'The hardware store'),
          '   ',
        );
        await tester.tap(find.text('Save label'));
        await tester.pumpAndSettle();
        // Cleared: the title falls back to the place's own name.
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text(hardwarePlace.name),
          ),
          findsWidgets,
        );
      });
    });

    testWidgets('explains a failed relabel', (tester) async {
      await withClock(Clock.fixed(noon), () async {
        final api = MockApiService();
        final saved = SavedPlace(id: 9, place: hardwarePlace);
        when(() => api.getBookmarks()).thenAnswer((_) async => [saved]);
        when(
          () => api.updateBookmarkGraphic(
            any(),
            any(),
            any(),
            customName: any(named: 'customName'),
          ),
        ).thenThrow(ApiException('down'));
        await open(tester, hardwarePlace, api: api);
        await tester.ensureVisible(find.text('Save label'));
        await tester.tap(find.text('Save label'));
        await tester.pumpAndSettle();
        expect(find.text("Couldn't save the label."), findsOneWidget);
      });
    });

    testWidgets('a place without a location has no map', (tester) async {
      await withClock(Clock.fixed(noon), () async {
        await open(
          tester,
          const Place(
            tomtomId: 'tt_nowhere',
            name: 'Nowhere',
            address: 'Unknown',
            location: LatLng(0, 0),
          ),
          bookmarks: const [],
        );
        expect(find.byType(AddressMapThumb), findsNothing);
        expect(find.text('Contact'), findsNothing);
      });
    });
  });
}

String _weekday(DateTime d) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
