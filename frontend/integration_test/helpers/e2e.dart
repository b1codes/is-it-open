import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/core/refractive_glass.dart';
import 'package:frontend/components/shared/side_menu.dart';
import 'package:frontend/core/env_config.dart';
import 'package:frontend/main.dart';
import 'package:frontend/services/api_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

/// The account `manage.py seed_e2e` creates (see e2e/README.md).
const seededUsername = 'e2e-seeded';
const seededPassword = 'e2e-password';

/// The stub as the backend (not the app) reaches it: by its compose service
/// name, or at 127.0.0.1 in the Docker-free stack (e2e/start-native.sh).
const _stubForBackend = String.fromEnvironment(
  'E2E_STUB_URL',
  defaultValue: 'http://stub:8090',
);

/// The stub's iCal feed, for the backend's /calendar/proxy to fetch.
const stubCalendarUrl = '$_stubForBackend/calendar/e2e.ics';
const stubEventTitle = 'E2E Dentist Appointment';

/// Where the stub geocodes every address (contracts/tomtom/fixtures/geocode.json).
const stubGeocodeLat = 39.80178;
const stubGeocodeLng = -89.64352;

/// What main() does before runApp, then a first request to the backend.
/// Call once, from setUpAll.
Future<void> initApp() async {
  tz.initializeTimeZones();
  await EnvConfig.init();
  // A cold backend (first password hash, first Firestore connection) can be
  // slow; take that hit here rather than in the first journey.
  await BackendApi().register('warmup');
}

/// A journey: a testWidgets that saves a screenshot when it fails (on the
/// web, `flutter drive` writes it to build/e2e-screenshots).
void journey(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } catch (_) {
      await _screenshot(description);
      rethrow;
    }
  });
}

Future<void> _screenshot(String description) async {
  // Only the web driver saves screenshots; elsewhere this would need a host.
  if (!kIsWeb) return;
  final name = description.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  try {
    await IntegrationTestWidgetsFlutterBinding.instance.takeScreenshot(name);
  } catch (e) {
    debugPrint('Could not take a screenshot: $e');
  }
}

/// Each journey starts signed out, with nothing stored on the device.
Future<void> resetDevice() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

/// A username no other run has used, so journeys never share an account.
String uniqueUsername(String prefix) {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = Random().nextInt(1 << 20).toRadixString(36);
  return 'e2e-$prefix-$stamp$salt';
}

class E2eUser {
  E2eUser(this.username, this.password, this.token);
  final String username;
  final String password;
  final String token;
}

/// The E2E backend's API, called directly to set up what a journey needs
/// but isn't about (an account to sign in with, a bookmark to edit).
class BackendApi {
  BackendApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: EnvConfig.apiBaseUrl,
          headers: {'Content-Type': 'application/json'},
        ),
      );

  final Dio _dio;

  Future<E2eUser> register(String prefix, {String password = 'pw-e2e'}) async {
    final username = uniqueUsername(prefix);
    final response = await _dio.post(
      '/auth/register',
      data: {'username': username, 'password': password},
    );
    return E2eUser(username, password, response.data['token'] as String);
  }

  Future<List<dynamic>> bookmarks(E2eUser user) async {
    final response = await _dio.get(
      '/places/bookmarks',
      options: Options(headers: {'Authorization': 'Bearer ${user.token}'}),
    );
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> profile(E2eUser user) async {
    final response = await _dio.get(
      '/auth/me',
      options: Options(headers: {'Authorization': 'Bearer ${user.token}'}),
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateProfile(E2eUser user, Map<String, dynamic> data) =>
      _dio.put(
        '/auth/me',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer ${user.token}'}),
      );
}

/// Retries [check] until it passes: for state the app saves in the
/// background, checked on the backend.
Future<void> eventually(
  Future<void> Function() check, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      return await check();
    } on TestFailure {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}

/// Stores [user]'s session the way a previous sign-in would, so the next
/// launch restores it.
Future<void> storeSession(E2eUser user) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('auth_token', user.token);
}

extension E2eTester on WidgetTester {
  /// Starts the app as main() does. [api] replaces the real API client.
  Future<void> launchApp({ApiService? api}) async {
    await pumpWidget(MyApp(key: UniqueKey(), apiService: api));
    await pump();
  }

  /// Closes the app and starts it again: state survives only on the device
  /// (SharedPreferences) and on the backend.
  Future<void> relaunchApp() async {
    await pumpWidget(const SizedBox.shrink());
    await pump();
    await launchApp();
  }

  /// Pumps frames until [finder] matches. The backend is real, so a response
  /// can take any time: pumpAndSettle may return before it arrives.
  Future<void> waitFor(
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('Timed out after $timeout waiting for $finder');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await pump();
    }
    await pump();
  }

  /// Pumps frames until [finder] stops matching.
  Future<void> waitForAbsent(
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('Timed out after $timeout waiting for $finder to go');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await pump();
    }
  }

  /// Lets animations and in-flight requests finish, without failing on
  /// animations that never settle (spinners, the map).
  Future<void> settle([
    Duration duration = const Duration(milliseconds: 600),
  ]) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pump();
    }
  }

  /// Taps [finder] once any route transition has finished (a tap during one
  /// lands on the route that's leaving), then lets the result settle.
  Future<void> tapAndSettle(Finder finder) async {
    await settle(const Duration(milliseconds: 400));
    await reveal(finder);
    await ensureVisible(finder.first);
    await tap(finder.first);
    await settle();
  }

  /// Scrolls the screen's main list until [finder] is built: a lazy list
  /// (a ListView on a phone-sized screen) doesn't build what's below the fold.
  Future<void> reveal(Finder finder) async {
    if (any(finder)) return;
    final lists = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    if (!any(lists)) return;
    await scrollUntilVisible(finder, 200, scrollable: lists.last);
    await pump();
  }

  /// Types into a text field, focusing it with a tap first, as a user would.
  Future<void> typeInto(Finder field, String text) async {
    await tapAndSettle(field);
    await enterText(field.first, text);
    await pump();
    expect(
      widget<EditableText>(
        find.descendant(of: field.first, matching: find.byType(EditableText)),
      ).controller.text,
      text,
      reason: 'the text should land in $field',
    );
  }

  Future<void> enterField(String label, String text) =>
      typeInto(find.widgetWithText(TextFormField, label), text);

  /// The desktop layout has a side menu; the phone layout a bottom bar.
  bool get isDesktopLayout => any(find.byType(SideMenu));

  /// Opens a tab (My Places, Calendar, Map, Search, Me) in either layout.
  Future<void> openTab(String label) async {
    final nav = isDesktopLayout
        ? find.byType(SideMenu)
        : find.byType(BottomNavigationBar);
    await tapAndSettle(find.descendant(of: nav, matching: find.text(label)));
    if (!isDesktopLayout && label != 'Map') await _expandSheet(label);
  }

  /// On a phone, a tab opens in a sheet at half height. Drags it fully open,
  /// as a user would on a short screen, so lists show more than a row or two.
  Future<void> _expandSheet(String label) async {
    final sheet = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(RefractiveGlass),
        )
        .first;
    // The calendar scrolls its own views, so its sheet is dragged by the
    // handle; every other tab's content drags the sheet.
    final grab =
        getTopLeft(sheet) +
        Offset(getSize(sheet).width / 2, label == 'Calendar' ? 12 : 80);
    await dragFrom(grab, Offset(0, -view.physicalSize.height));
    await settle();
  }

  Future<void> signIn(String username, String password) async {
    await waitFor(find.text('LOCAL SIGN IN'));
    await enterField('Email Address', username);
    await enterField('Password', password);
    await tapAndSettle(find.text('LOCAL SIGN IN'));
  }

  /// Logs out from the side menu (desktop) or the Me tab (phone).
  Future<void> logOut() async {
    if (isDesktopLayout) {
      await tapAndSettle(
        find.descendant(
          of: find.byType(SideMenu),
          matching: find.text('Logout'),
        ),
      );
    } else {
      await openTab('Me');
      await tapAndSettle(find.widgetWithText(OutlinedButton, 'Logout'));
    }
  }
}
