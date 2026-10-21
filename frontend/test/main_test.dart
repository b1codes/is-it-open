import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/profile/settings_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fixtures.dart';
import 'helpers/mocks.dart';
import 'helpers/pump_app.dart';

/// Counts the loads MyApp's auth listener dispatches, and can fail profile
/// saves or sign in as someone other than [demoUser].
class _CountingApi extends FakeApiService {
  _CountingApi({this.failProfileSaves = false, this.loginAs})
    : super(latency: Duration.zero);

  final bool failProfileSaves;
  final User? loginAs;
  int bookmarkLoads = 0;
  int calendarLoads = 0;

  @override
  Future<List<SavedPlace>> getBookmarks() {
    bookmarkLoads++;
    return super.getBookmarks();
  }

  @override
  Future<String> getCalendarFromUrl(String url) {
    calendarLoads++;
    return super.getCalendarFromUrl(url);
  }

  @override
  Future<User> updateProfile(User user) async {
    if (failProfileSaves) throw ApiException('Failed to update profile: 500');
    return super.updateProfile(user);
  }

  @override
  Future<User> login(String username, String password) async =>
      loginAs ?? await super.login(username, password);
}

// The whole app (MyApp's providers and auth routing) against FakeApiService.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> start(
    WidgetTester tester, {
    FakeApiService? api,
    Size size = phoneSize,
  }) async {
    FakeGeolocator.install(addTearDown);
    tester.setViewport(size);
    await tester.pumpWidget(
      MyApp(apiService: api ?? FakeApiService(latency: Duration.zero)),
    );
  }

  testWidgets('shows a spinner, then login without a stored session', (
    tester,
  ) async {
    await start(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a stored session goes straight to home', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'tok',
      'auth_user_json': jsonEncode(demoUser.toJson()),
    });
    await start(tester);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.unmount();
  });

  testWidgets('logging in opens home; logging out returns to login', (
    tester,
  ) async {
    await start(tester, size: desktopSize);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'demo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret',
    );
    await tester.tap(find.text('LOCAL SIGN IN'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.text('Logout')); // in the side menu
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.unmount();
  });

  testWidgets('registering from the sign-up screen opens home', (tester) async {
    await start(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join the neighborhood'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name'),
      'newcomer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'new@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret',
    );
    await tester.tap(find.text('JOIN'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.unmount();
  });

  void storeSession(User user) => SharedPreferences.setMockInitialValues({
    'auth_token': 'tok',
    'auth_user_json': jsonEncode(user.toJson()),
  });

  T read<T>(WidgetTester tester) =>
      tester.element(find.byType(MaterialApp)).read<T>();

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('Settings')); // in the side menu
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  group('a profile save is not a sign-in', () {
    for (final fails in [false, true]) {
      testWidgets(
        'a ${fails ? 'failed' : 'successful'} save keeps Settings open '
        'and reloads nothing',
        (tester) async {
          storeSession(demoUser);
          final api = _CountingApi(failProfileSaves: fails);
          await start(tester, api: api, size: desktopSize);
          await tester.pumpAndSettle();
          await openSettings(tester);
          final bookmarkLoads = api.bookmarkLoads;
          final calendarLoads = api.calendarLoads;

          await tester.tap(
            find.widgetWithText(SwitchListTile, 'Use Current Location'),
          );
          await tester.pumpAndSettle();

          expect(
            read<AuthBloc>(tester).state,
            fails ? isA<ProfileUpdateFailure>() : isA<ProfileUpdateSuccess>(),
          );
          expect(find.byType(SettingsScreen), findsOneWidget);
          expect(
            find.text(
              fails
                  ? 'Exception: Failed to update profile: 500'
                  : 'Settings saved successfully!',
            ),
            findsOneWidget,
          );
          expect(api.bookmarkLoads, bookmarkLoads);
          expect(api.calendarLoads, calendarLoads);
          await tester.unmount();
        },
      );
    }
  });

  testWidgets('signing out closes pushed screens', (tester) async {
    storeSession(demoUser);
    await start(tester, api: _CountingApi(), size: desktopSize);
    await tester.pumpAndSettle();
    await openSettings(tester);

    read<AuthBloc>(tester).add(LogoutRequested());
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.unmount();
  });

  testWidgets("the next user doesn't see the last one's calendar", (
    tester,
  ) async {
    // A has a calendar subscription; B, on the same device, has none.
    storeSession(demoUser);
    final userB = User(id: 2, username: 'bea', token: 'tok-b');
    final api = _CountingApi(loginAs: userB);
    await start(tester, api: api, size: desktopSize);
    await tester.pumpAndSettle();
    expect(api.calendarLoads, 1);
    expect(read<CalendarDataBloc>(tester).state.remoteEvents, isNotEmpty);

    await tester.tap(find.text('Logout')); // in the side menu
    await tester.pumpAndSettle();
    expect(read<CalendarDataBloc>(tester).state.remoteEvents, isEmpty);
    expect(read<CalendarDataBloc>(tester).state.savedPlaces, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'bea',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret',
    );
    await tester.tap(find.text('LOCAL SIGN IN'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(read<AuthBloc>(tester).state, AuthAuthenticated(user: userB));
    expect(read<CalendarDataBloc>(tester).state.remoteEvents, isEmpty);
    expect(api.calendarLoads, 1, reason: 'B has no subscription to load');
    await tester.unmount();
  });
}
