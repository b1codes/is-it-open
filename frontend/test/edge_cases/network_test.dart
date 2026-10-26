import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';

// The app offline (every request fails) and on a network that never
// answers: each main screen says so or keeps loading, and nothing throws.
// See "Monkey testing" in TESTING.md.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  /// Two seconds of frames. In short steps: a screen sends its request
  /// while building, so one long pump would end before the reply.
  Future<void> wait(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Starts the app on [api], signed in from a stored session if
  /// [signedIn]. With a [Duration]-less api nothing ever settles, so this
  /// pumps a fixed time instead.
  Future<void> start(
    WidgetTester tester,
    FakeApiService api, {
    bool signedIn = true,
    Size size = phoneSize,
  }) async {
    if (signedIn) {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'tok',
        'auth_user_json': jsonEncode(demoUser.toJson()),
      });
    }
    FakeGeolocator.install(addTearDown);
    tester.setViewport(size);
    await tester.pumpWidget(MyApp(apiService: api));
    await wait(tester);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await wait(tester);
  }

  group('offline', () {
    FakeApiService offline() =>
        FakeApiService(latency: const Duration(milliseconds: 50), fail: true);

    testWidgets('a stored session still opens the app', (tester) async {
      await start(tester, offline());
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(MapScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });

    for (final (size, layout) in [
      (phoneSize, 'phone'),
      (desktopSize, 'desktop'),
    ]) {
      testWidgets('every tab opens and says what failed ($layout)', (
        tester,
      ) async {
        await start(tester, offline(), size: size);
        for (final (tab, screen) in [
          ('My Places', MyPlacesScreen),
          ('Calendar', CalendarScreen),
          ('Search', SearchScreen),
          ('Me', MeScreen),
          ('Map', MapScreen),
        ]) {
          await tester.tap(find.text(tab).last);
          await wait(tester);
          expect(find.byType(screen), findsOneWidget, reason: tab);
          expect(tester.takeException(), isNull, reason: tab);
          if (screen == MyPlacesScreen) {
            expect(find.text("Couldn't load your places."), findsOneWidget);
          }
          if (screen == SearchScreen) {
            await search(tester, 'coffee');
            expect(find.textContaining('Error:'), findsOneWidget);
          }
        }
        await tester.unmount();
      });
    }

    testWidgets('signing in says it failed', (tester) async {
      await start(tester, offline(), signedIn: false);
      await tester.enterText(field('Email Address'), 'demo');
      await tester.enterText(field('Password'), 'secret');
      await tester.tap(find.text('LOCAL SIGN IN'));
      await wait(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });

    testWidgets('saving the profile says it failed', (tester) async {
      await start(tester, offline(), size: desktopSize);
      await tester.tap(find.text('Me').last);
      await wait(tester);
      await tester.enterText(field('First Name'), 'Robin');
      await tester.ensureVisible(find.text('Save Profile'));
      await tester.tap(find.text('Save Profile'));
      await wait(tester);
      expect(find.text('Save Profile'), findsOneWidget); // not spinning
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });
  });

  group('a network that never answers', () {
    FakeApiService stalled() => _StalledApi();

    testWidgets('signing in keeps showing progress', (tester) async {
      await start(tester, stalled(), signedIn: false);
      await tester.enterText(field('Email Address'), 'demo');
      await tester.enterText(field('Password'), 'secret');
      await tester.tap(find.text('LOCAL SIGN IN'));
      await wait(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });

    testWidgets('every tab opens while its data loads', (tester) async {
      await start(tester, stalled());
      for (final (tab, screen) in [
        ('My Places', MyPlacesScreen),
        ('Calendar', CalendarScreen),
        ('Search', SearchScreen),
        ('Me', MeScreen),
        ('Map', MapScreen),
      ]) {
        await tester.tap(find.text(tab).last);
        await wait(tester);
        expect(find.byType(screen), findsOneWidget, reason: tab);
        expect(tester.takeException(), isNull, reason: tab);
      }
      await tester.tap(find.text('Search').last);
      await wait(tester);
      await search(tester, 'coffee');
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.unmount();
    });
  });
}

/// Answers the profile check on startup, so a stored session opens the app
/// (the real client gives up on it after its timeouts), then never answers
/// anything else.
class _StalledApi extends FakeApiService {
  _StalledApi() : super(latency: null);

  @override
  Future<User> getProfile() async => demoUser;
}
