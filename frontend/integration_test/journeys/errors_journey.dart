import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/e2e.dart';

/// Nothing listens on port 9 (discard), so this is a backend that's down.
ApiService _backendDown() => ApiService(baseUrl: 'http://127.0.0.1:9/api');

/// Failures the app should survive with a clear message instead of a crash
/// or a blank screen.
void errorJourneys() {
  journey('with the backend down, signing in fails with a message', (
    tester,
  ) async {
    await tester.launchApp(api: _backendDown());
    await tester.signIn(seededUsername, seededPassword);

    await tester.waitFor(find.byType(SnackBar));
    expect(find.textContaining('Failed to login'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  journey('with the backend down, a signed-in user keeps their cached '
      'session and sees why their places are missing', (tester) async {
    await tester.launchApp();
    await tester.signIn(seededUsername, seededPassword);
    await tester.waitFor(find.byType(HomeScreen));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.launchApp(api: _backendDown());
    await tester.waitFor(find.byType(HomeScreen));
    await tester.openTab('My Places');
    await tester.waitFor(find.text("Couldn't load your places."));
    expect(find.text('Try again'), findsOneWidget);
  });

  journey('a TomTom outage leaves search usable', (tester) async {
    final user = await BackendApi().register('outage');
    await storeSession(user);
    await tester.launchApp();
    await tester.waitFor(find.byType(HomeScreen));

    // The stub answers any query containing "outage" with a 503.
    await tester.openTab('Search');
    final field = find.widgetWithText(TextField, 'Search for a place...');
    await tester.waitFor(field);
    await tester.typeInto(field, 'pizza outage');
    await tester.tapAndSettle(find.widgetWithText(ElevatedButton, 'Search'));

    await tester.waitFor(find.text('No results found'));
    expect(find.text('Create a New Place'), findsOneWidget);
  });

  journey('an expired session goes back to sign-in and is cleared', (
    tester,
  ) async {
    // A token the backend doesn't know: what a revoked one looks like.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', 'expired-0123456789abcdef');
    await prefs.setString(
      'auth_user_json',
      '{"id": 1, "username": "$seededUsername", "token": "expired"}',
    );

    await tester.launchApp();
    await tester.waitFor(find.byType(LoginScreen));
    expect(find.byType(HomeScreen), findsNothing);
    await prefs.reload();
    expect(prefs.getString('auth_token'), isNull);

    // Signing in again works.
    await tester.signIn(seededUsername, seededPassword);
    await tester.waitFor(find.byType(HomeScreen));
  });
}
