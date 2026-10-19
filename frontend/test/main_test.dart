import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fixtures.dart';
import 'helpers/mocks.dart';
import 'helpers/pump_app.dart';

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
}
