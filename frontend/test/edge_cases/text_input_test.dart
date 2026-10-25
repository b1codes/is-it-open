import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/places/quick_add_place_sheet.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';
import '../helpers/recording_api.dart';
import '../../integration_test/helpers/monkey.dart';

// What people type that a form might not expect: emoji (with skin tones,
// ZWJ sequences and flags), combining marks, right-to-left and CJK text,
// control characters, markup and SQL, and very long strings. Each reaches
// the API as typed, and shows without breaking a layout. See "Monkey
// testing" in TESTING.md.

/// [monkeyStrings] with something visible in them, and two long ones.
final _inputs = [
  for (final s in monkeyStrings)
    if (s.trim().isNotEmpty) s,
  'A' * 500,
  List.filled(80, 'Café 東京 👨‍👩‍👧‍👦').join(' '),
];

String _describe(String s) =>
    s.length > 20 ? '${s.length} characters' : '"${s.replaceAll('\n', r'\n')}"';

// Monday 19 Oct 2026, noon.
final _noon = DateTime(2026, 10, 19, 12);

void main() {
  setUpAll(registerFallbacks);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('search sends each query as typed', (tester) async {
    final api = RecordingApi();
    FakeGeolocator.install(addTearDown);
    await tester.pumpApp(const SearchScreen(), api: api);
    await tester.pumpAndSettle();
    for (final input in _inputs) {
      await tester.enterText(find.byType(TextField), input);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.last('searchPlaces'), [input], reason: _describe(input));
      expect(tester.takeException(), isNull, reason: _describe(input));
    }
  });

  testWidgets('quick add saves each name and address as typed, trimmed', (
    tester,
  ) async {
    final api = RecordingApi();
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const QuickAddPlaceSheet(),
          ),
          child: const Text('open'),
        ),
      ),
      api: api,
    );
    for (final input in _inputs) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Name'), ' $input ');
      await tester.enterText(field('Address'), input);
      await tester.tap(find.text('Save place'));
      await tester.pumpAndSettle();
      final saved = api.last('savePlace').single as Place;
      expect(saved.name, input.trim(), reason: _describe(input));
      expect(saved.address, input.trim(), reason: _describe(input));
      expect(find.byType(QuickAddPlaceSheet), findsNothing);
      expect(tester.takeException(), isNull, reason: _describe(input));
    }
  });

  testWidgets('sign-up sends the name as typed', (tester) async {
    final api = RecordingApi();
    FakeGeolocator.install(addTearDown);
    tester.setViewport(phoneSize);
    await tester.pumpWidget(MyApp(apiService: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join the neighborhood'));
    await tester.pumpAndSettle();
    const name = 'Zoë 👩🏽‍💻 أحمد';
    await tester.enterText(field('Full Name'), name);
    await tester.enterText(field('Email Address'), 'zoe@example.com');
    await tester.enterText(field('Password'), 'p@ss 🔑 word');
    await tester.tap(find.text('JOIN'));
    await tester.pumpAndSettle();
    expect(api.last('register'), [name, 'p@ss 🔑 word', 'zoe@example.com']);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.unmount();
  });

  testWidgets('the profile saves each name as typed, and shows it', (
    tester,
  ) async {
    final api = RecordingApi();
    await tester.pumpApp(const MeScreen(), api: api, size: desktopSize);
    for (final input in _inputs) {
      await tester.enterText(field('First Name'), input);
      await tester.enterText(field('Last Name'), input);
      await tester.ensureVisible(find.text('Save Profile'));
      await tester.tap(find.text('Save Profile'));
      await tester.pumpAndSettle();
      final fields = api.last('updateProfileFields').single as Map;
      expect(fields['first_name'], input.trim(), reason: _describe(input));
      expect(tester.takeException(), isNull, reason: _describe(input));
    }
  });

  group('places named oddly', () {
    final places = [
      for (final (i, input) in _inputs.indexed)
        SavedPlace(
          id: 100 + i,
          customName: i.isEven ? input : null,
          isPinned: i % 3 == 0,
          place: Place(
            tomtomId: 'tt_odd_$i',
            name: input,
            address: input,
            location: coffeePlace.location,
            categories: [input],
            hours: coffeePlace.hours,
          ),
        ),
    ];

    for (final (size, layout) in [
      (phoneSize, 'phone'),
      (desktopSize, 'desktop'),
    ]) {
      testWidgets('lay out in My Places, as a list and a grid ($layout)', (
        tester,
      ) async {
        await withClock(Clock.fixed(_noon), () async {
          await tester.pumpApp(
            const MyPlacesScreen(),
            bookmarks: places,
            size: size,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Grid view'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.unmount();
        });
      });

      testWidgets('lay out on the map and its sheet ($layout)', (tester) async {
        await withClock(Clock.fixed(_noon), () async {
          FakeGeolocator.install(addTearDown);
          await tester.pumpApp(
            const HomeScreen(),
            bookmarks: places,
            size: size,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.unmount();
        });
      });
    }

    for (final saved in places.take(6)) {
      testWidgets('lay out in the details of ${_describe(saved.place.name)}', (
        tester,
      ) async {
        await withClock(Clock.fixed(_noon), () async {
          await tester.pumpApp(
            PlaceDetailScreen(place: saved.place),
            bookmarks: places,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.unmount();
        });
      });
    }
  });
}
