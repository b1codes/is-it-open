import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/side_menu.dart';
import 'package:frontend/main.dart';
import 'package:frontend/screens/auth/forgot_password_screen.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';

// The screen changing shape under the app: a phone turned on its side (which
// switches to the side-menu layout, past 800 wide) and back, and the largest
// text size the app supports (2×, see "Accessibility" in TESTING.md) in both
// orientations. See "Monkey testing" in TESTING.md.

const _landscape = Size(844, 390);

const _tabs = [
  ('My Places', MyPlacesScreen),
  ('Calendar', CalendarScreen),
  ('Search', SearchScreen),
  ('Me', MeScreen),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> start(WidgetTester tester, {bool signedIn = true}) async {
    if (signedIn) {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'tok',
        'auth_user_json': jsonEncode(demoUser.toJson()),
      });
    }
    FakeGeolocator.install(addTearDown);
    tester.setViewport(phoneSize);
    await tester.pumpWidget(
      MyApp(apiService: FakeApiService(latency: Duration.zero)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  /// Taps [tab] in the bottom bar or the side menu, scrolling the side
  /// menu to it when the window is short.
  Future<void> openTab(WidgetTester tester, String tab) async {
    final menu = find.byType(SideMenu);
    if (!tester.any(menu)) {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(tab),
        ),
      );
      return;
    }
    final item = find.descendant(of: menu, matching: find.text(tab));
    await tester.scrollUntilVisible(
      item,
      50,
      scrollable: find.descendant(of: menu, matching: find.byType(Scrollable)),
    );
    await tester.ensureVisible(item); // all of it, not just its top
    await tester.pumpAndSettle();
    await tester.tap(item);
  }

  group('turning a phone', () {
    for (final (tab, screen) in _tabs) {
      testWidgets('keeps $tab open, on its side and back', (tester) async {
        await start(tester);
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();

        await resize(tester, _landscape);
        expect(find.byType(SideMenu), findsOneWidget);
        expect(find.byType(screen), findsOneWidget);
        expect(tester.takeException(), isNull);

        await resize(tester, phoneSize);
        expect(find.byType(SideMenu), findsNothing);
        expect(find.byType(screen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.unmount();
      });
    }
  });

  group('at 2× text', () {
    setUp(() {
      TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .textScaleFactorTestValue =
          2;
    });
    tearDown(
      TestWidgetsFlutterBinding
          .instance
          .platformDispatcher
          .clearTextScaleFactorTestValue,
    );

    for (final (size, orientation) in [
      (phoneSize, 'upright'),
      (_landscape, 'on its side'),
    ]) {
      for (final (tab, screen) in _tabs) {
        testWidgets('$tab fits a phone $orientation', (tester) async {
          await start(tester);
          await resize(tester, size);
          await openTab(tester, tab);
          await tester.pumpAndSettle();
          expect(find.byType(screen), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.unmount();
        });
      }

      testWidgets('signing in and up fit a phone $orientation', (tester) async {
        await start(tester, signedIn: false);
        await resize(tester, size);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('Forgot password?'));
        await tester.tap(find.text('Forgot password?'));
        await tester.pumpAndSettle();
        expect(find.byType(ForgotPasswordScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Join the neighborhood'));
        await tester.tap(find.text('Join the neighborhood'));
        await tester.pumpAndSettle();
        expect(find.byType(RegisterScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.unmount();
      });
    }
  });
}
