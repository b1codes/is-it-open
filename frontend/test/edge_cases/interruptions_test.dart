import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';
import 'package:frontend/screens/places/plan_visit_screen.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';
import '../helpers/recording_api.dart';

// Work interrupted part-way: leaving a screen while its request is out,
// and the app going to the background and back. See "Monkey testing" in
// TESTING.md.

const _latency = Duration(milliseconds: 800);

/// The system sends the app to the background, then brings it back.
Future<void> backgroundAndBack(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump(const Duration(seconds: 5));
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<RecordingApi> start(
    WidgetTester tester, {
    bool signedIn = false,
    Size size = phoneSize,
    bool fail = false,
  }) async {
    if (signedIn) {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'tok',
        'auth_user_json': jsonEncode(demoUser.toJson()),
      });
    }
    final api = RecordingApi(latency: _latency, fail: fail);
    FakeGeolocator.install(addTearDown);
    tester.setViewport(size);
    await tester.pumpWidget(MyApp(apiService: api));
    await tester.pumpAndSettle();
    return api;
  }

  group('leaving mid-request', () {
    for (final fails in [false, true]) {
      testWidgets(
        'going back from sign-up before it ${fails ? 'fails' : 'answers'}',
        (tester) async {
          await start(tester, fail: fails);
          await tester.tap(find.text('Join the neighborhood'));
          await tester.pumpAndSettle();
          await tester.enterText(field('Full Name'), 'newcomer');
          await tester.enterText(field('Email Address'), 'new@example.com');
          await tester.enterText(field('Password'), 'secret');
          await tester.tap(find.text('JOIN'));
          await tester.pump();
          await tester.binding.handlePopRoute(); // the system back button
          await tester.pumpAndSettle();

          expect(find.byType(fails ? LoginScreen : HomeScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.unmount();
        },
      );
    }

    testWidgets('switching tabs while the profile saves', (tester) async {
      final api = await start(tester, signedIn: true);
      await tester.tap(find.text('Me'));
      await tester.pumpAndSettle();
      await tester.enterText(field('First Name'), 'Robin');
      await tester.ensureVisible(find.text('Save Profile'));
      await tester.tap(find.text('Save Profile'));
      await tester.pump();
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(api.count('updateProfileFields'), 1);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Me'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('First Name')).controller!.text,
        'Robin',
      );
      await tester.unmount();
    });

    testWidgets('going back while a visit length saves', (tester) async {
      final api = RecordingApi(latency: _latency);
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlanVisitScreen(
                  place: coffeePlace,
                  saved: SavedPlace(id: 1, place: coffeePlace),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        api: api,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(PlanVisitScreen), findsNothing);
      expect(api.count('updateVisitLength'), 1);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });

    testWidgets('going back while a place loads', (tester) async {
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaceDetailScreen(place: coffeePlace),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        apiLatency: _latency,
      );
      await tester.tap(find.text('open'));
      await tester.pump(); // a new route is offstage for its first frame
      await tester.pump(const Duration(milliseconds: 400)); // still loading
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });
  });

  group('to the background and back', () {
    for (final (size, layout) in [
      (phoneSize, 'phone'),
      (desktopSize, 'desktop'),
    ]) {
      for (final (tab, screen) in [
        ('My Places', MyPlacesScreen),
        ('Calendar', CalendarScreen),
        ('Search', SearchScreen),
        ('Me', MeScreen),
      ]) {
        testWidgets('keeps $tab open ($layout)', (tester) async {
          await start(tester, signedIn: true, size: size);
          await tester.tap(find.text(tab).last);
          await tester.pump(); // its data is still loading
          await backgroundAndBack(tester);
          await tester.pumpAndSettle();
          expect(find.byType(screen), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.unmount();
        });
      }
    }

    testWidgets('while signing in', (tester) async {
      await start(tester);
      await tester.enterText(field('Email Address'), 'demo');
      await tester.enterText(field('Password'), 'secret');
      await tester.tap(find.text('LOCAL SIGN IN'));
      await tester.pump();
      await backgroundAndBack(tester);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });
  });
}
