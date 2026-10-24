import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/places/saved_place_row.dart';
import 'package:frontend/components/places/saved_place_tile.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/utils/graphics_helper.dart';
import 'package:frontend/utils/place_status.dart';

import '../../helpers/fixtures.dart';

// Covers saved_place_row.dart and saved_place_tile.dart: the list and grid
// views of a saved place share the same contract.
typedef _Builder =
    Widget Function({
      required SavedPlace savedPlace,
      required int colorIndex,
      required PlaceStatus status,
      required bool isOnToday,
      required VoidCallback onTap,
      required VoidCallback onToggleToday,
      required VoidCallback onLongPress,
    });

void main() {
  final views = <String, _Builder>{
    'row': SavedPlaceRow.new,
    'tile':
        ({
          required savedPlace,
          required colorIndex,
          required status,
          required isOnToday,
          required onTap,
          required onToggleToday,
          required onLongPress,
        }) => SizedBox(
          width: 200,
          height: 190,
          child: SavedPlaceTile(
            savedPlace: savedPlace,
            colorIndex: colorIndex,
            status: status,
            isOnToday: isOnToday,
            onTap: onTap,
            onToggleToday: onToggleToday,
            onLongPress: onLongPress,
          ),
        ),
  };

  for (final MapEntry(key: name, value: build) in views.entries) {
    group(name, () {
      late List<String> calls;

      Future<void> pump(
        WidgetTester tester,
        SavedPlace place, {
        int colorIndex = 0,
        bool isOnToday = false,
      }) async {
        calls = [];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: build(
                  savedPlace: place,
                  colorIndex: colorIndex,
                  status: openStatus,
                  isOnToday: isOnToday,
                  onTap: () => calls.add('tap'),
                  onToggleToday: () => calls.add('today'),
                  onLongPress: () => calls.add('long'),
                ),
              ),
            ),
          ),
        );
      }

      testWidgets('prefers the custom name and shows the status', (
        tester,
      ) async {
        await pump(tester, sampleSavedPlaces[1]); // "Friday burger spot"
        expect(find.text('Friday burger spot'), findsOneWidget);
        expect(find.text(bistroPlace.name), findsNothing);
        expect(find.text(bistroPlace.address), findsOneWidget);
        expect(find.text('Open · until 6pm'), findsOneWidget);
      });

      testWidgets('falls back to the place name', (tester) async {
        await pump(tester, sampleSavedPlaces[0]);
        expect(find.text(coffeePlace.name), findsOneWidget);
      });

      testWidgets('routes taps, long presses and the today toggle', (
        tester,
      ) async {
        await pump(tester, sampleSavedPlaces[0]);
        await tester.tap(find.text(coffeePlace.address));
        await tester.longPress(find.text(coffeePlace.address));
        await tester.tap(find.byIcon(Icons.add_rounded));
        expect(calls, ['tap', 'long', 'today']);
      });

      testWidgets('the toggle reflects today\'s route', (tester) async {
        await pump(tester, sampleSavedPlaces[0], isOnToday: true);
        expect(
          find.bySemanticsLabel(RegExp("^Remove from today's route")),
          findsOne,
        );
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        await pump(tester, sampleSavedPlaces[0]);
        expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      });

      testWidgets('a place without a color takes its palette color', (
        tester,
      ) async {
        // The same color as its pin on the map and its calendar blocks.
        final uncolored = SavedPlace(
          id: 9,
          place: coffeePlace,
          icon: 'local_cafe',
        );
        await pump(tester, uncolored, colorIndex: 2);
        final circle =
            tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: find.byIcon(Icons.local_cafe),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(circle.color, GraphicsHelper.colorForSavedPlace(uncolored, 2));
      });

      testWidgets('a very long name does not overflow', (tester) async {
        await pump(tester, sampleSavedPlaces[4]); // long hardware store name
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('the row labels its toggle and can hide its divider', (
    tester,
  ) async {
    Future<void> pump({required bool divider, required bool onToday}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  SavedPlaceRow(
                    savedPlace: sampleSavedPlaces[0],
                    colorIndex: 0,
                    status: openStatus,
                    isOnToday: onToday,
                    onTap: () {},
                    onToggleToday: () {},
                    onLongPress: () {},
                    showDivider: divider,
                  ),
                ],
              ),
            ),
          ),
        );
    await pump(divider: true, onToday: false);
    expect(find.text('Today'), findsOneWidget);
    final withDivider = tester.getSize(find.byType(SavedPlaceRow)).height;
    await pump(divider: false, onToday: true);
    expect(find.text('On Today'), findsOneWidget);
    expect(
      tester.getSize(find.byType(SavedPlaceRow)).height,
      lessThan(withDivider),
    );
  });
}
