import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/places/quick_add_place_sheet.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/places/plan_visit_screen.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';
import '../helpers/recording_api.dart';

// Impatient taps on the main forms: a double tap on submit, and more taps
// while the request is in flight. Each must send one request, and the
// screen must still end up where one tap would leave it. See "Monkey
// testing" in TESTING.md.

/// Two taps a double tap apart, then two more while the request is out, all
/// on the spot where [button] was (a busy button may swap its label for a
/// spinner).
Future<void> hammer(WidgetTester tester, Finder button) async {
  final at = tester.getCenter(button);
  await tester.tapAt(at);
  for (final gap in [60, 100, 100]) {
    await tester.pump(Duration(milliseconds: gap));
    await tester.tapAt(at);
  }
}

const _latency = Duration(milliseconds: 500);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<RecordingApi> startSignedOut(WidgetTester tester) async {
    final api = RecordingApi(latency: _latency);
    FakeGeolocator.install(addTearDown);
    tester.setViewport(phoneSize);
    await tester.pumpWidget(MyApp(apiService: api));
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('signing in sends one request', (tester) async {
    final api = await startSignedOut(tester);
    await tester.enterText(field('Email Address'), 'demo');
    await tester.enterText(field('Password'), 'secret');
    await hammer(tester, find.text('LOCAL SIGN IN'));
    await tester.pumpAndSettle();
    expect(api.count('login'), 1);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.unmount();
  });

  testWidgets('joining sends one request', (tester) async {
    final api = await startSignedOut(tester);
    await tester.tap(find.text('Join the neighborhood'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Full Name'), 'newcomer');
    await tester.enterText(field('Email Address'), 'new@example.com');
    await tester.enterText(field('Password'), 'secret');
    await hammer(tester, find.text('JOIN'));
    await tester.pumpAndSettle();
    expect(api.count('register'), 1);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.unmount();
  });

  testWidgets('saving a profile sends one request', (tester) async {
    final api = RecordingApi(latency: _latency);
    await tester.pumpApp(const MeScreen(), api: api, size: desktopSize);
    await tester.enterText(field('First Name'), 'Avery J');
    await tester.ensureVisible(find.text('Save Profile'));
    await hammer(tester, find.text('Save Profile'));
    await tester.pumpAndSettle();
    expect(api.count('updateProfileFields'), 1);
    expect(find.text('Profile saved successfully!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick add saves the place once', (tester) async {
    final api = RecordingApi(latency: _latency);
    Object? result;
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const QuickAddPlaceSheet(),
          ),
          child: const Text('open'),
        ),
      ),
      api: api,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Name'), 'Trailhead');
    await tester.enterText(field('Address'), '1 Forest Rd');
    await hammer(tester, find.text('Save place'));
    await tester.pumpAndSettle();
    expect(api.count('savePlace'), 1);
    expect(api.count('bookmarkPlace'), 1);
    expect(result, isNotNull);
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visit length is saved once, and others wait for it', (
    tester,
  ) async {
    final api = RecordingApi(latency: _latency);
    await tester.pumpApp(
      PlanVisitScreen(
        place: coffeePlace,
        saved: SavedPlace(id: 1, place: coffeePlace),
      ),
      api: api,
    );
    await hammer(tester, find.text('30 min'));
    await tester.tap(find.text('1 hr'), warnIfMissed: false); // still saving
    await tester.pumpAndSettle();
    expect(api.count('updateVisitLength'), 1);
    expect(api.last('updateVisitLength'), [coffeePlace.tomtomId, 30]);
    expect(tester.takeException(), isNull);
  });
}
