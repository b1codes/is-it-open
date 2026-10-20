import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/places/status_pill.dart';
import 'package:frontend/components/shared/thermal_button.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:frontend/utils/places_theme.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';

// What a screen reader announces: labels on icon-only buttons, status pills
// that say whether a place is open, and map markers it can reach and press.
// The catalog-wide guideline checks are in
// widgetbook/test/accessibility_test.dart.

void main() {
  group('icon-only buttons have labels', () {
    final screens = <String, (Widget, Size)>{
      'home (phone)': (const HomeScreen(), phoneSize),
      'home (desktop)': (const HomeScreen(), desktopSize),
      'map (phone)': (const MapScreen(), phoneSize),
      'calendar (phone)': (const CalendarScreen(), phoneSize),
      'calendar (desktop)': (const CalendarScreen(), desktopSize),
      'my places': (const MyPlacesScreen(), desktopSize),
      'search': (const SearchScreen(), desktopSize),
      'profile': (const MeScreen(), desktopSize),
    };

    for (final MapEntry(key: name, value: (screen, size)) in screens.entries) {
      testWidgets(name, (tester) async {
        final semantics = tester.ensureSemantics();
        FakeGeolocator.install(addTearDown);
        await tester.pumpApp(screen, size: size);
        await tester.pumpAndSettle();

        final buttons = find.byWidgetPredicate(
          (w) => w is IconButton || w is PopupMenuButton,
        );
        for (final button in buttons.evaluate()) {
          final data = tester
              .getSemantics(find.byWidget(button.widget))
              .getSemanticsData();
          expect(
            data.label.isNotEmpty || data.tooltip.isNotEmpty,
            isTrue,
            reason: '${button.widget} has no label or tooltip',
          );
        }
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.unmount();
        semantics.dispose();
      });
    }
  });

  group('status pills say the status in words', () {
    const expected = {
      PlaceStatusKind.open: 'Open',
      PlaceStatusKind.closingSoon: 'Closes',
      PlaceStatusKind.closed: 'Closed',
      PlaceStatusKind.unknown: 'Hours unknown',
    };
    for (final MapEntry(key: kind, value: word) in expected.entries) {
      testWidgets(kind.name, (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpApp(
          Center(child: StatusPill(status: sampleStatuses[kind]!)),
        );
        // The color and dot carry no meaning a screen reader could miss.
        expect(find.semantics.byLabel(RegExp('^$word')), findsOne);
        await tester.unmount();
        semantics.dispose();
      });
    }
  });

  group('map markers', () {
    Future<void> pumpMap(
      WidgetTester tester, {
      void Function(SavedPlace)? onPlaceTapped,
    }) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(
        Scaffold(body: MapScreen(embedded: true, onPlaceTapped: onPlaceTapped)),
        size: desktopSize,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('are announced by name', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpMap(tester);

      expect(find.semantics.byLabel('Map'), findsOne);
      expect(find.semantics.byLabel('Your location'), findsOne);
      expect(find.semantics.byLabel('Home'), findsOne);
      expect(find.semantics.byLabel('Work'), findsOne);
      // The pinned places, by their custom name where they have one.
      expect(find.semantics.byLabel('Blue Bottle Coffee'), findsOne);
      expect(find.semantics.byLabel('Friday burger spot'), findsOne);

      await tester.unmount();
      semantics.dispose();
    });

    testWidgets('open a place from a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      final tapped = <SavedPlace>[];
      await pumpMap(tester, onPlaceTapped: tapped.add);

      final marker = find.semantics.byLabel('Friday burger spot');
      expect(marker, containsSemantics(isButton: true, hasTapAction: true));
      tester.semantics.tap(marker);
      expect(tapped.single.customName, 'Friday burger spot');

      await tester.unmount();
      semantics.dispose();
    });

    testWidgets('are at least 48×48', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpMap(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.unmount();
      semantics.dispose();
    });
  });

  testWidgets('a button keeps its label while it loads', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpApp(
      Center(
        child: ThermalButton(
          isLoading: true,
          onPressed: () {},
          child: const Text('JOIN'),
        ),
      ),
    );
    // The spinner hides the label; it used to drop it from semantics too,
    // leaving an unnamed button.
    expect(
      tester.getSemantics(find.byType(ThermalButton)),
      containsSemantics(label: 'JOIN', isButton: true, isEnabled: false),
    );
    await tester.unmount();
    semantics.dispose();
  });
}
