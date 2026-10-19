import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/profile/settings_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

void main() {
  setUpAll(registerFallbacks);

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save Profile'));
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();
  }

  User sentUser(MockApiService api) =>
      verify(() => api.updateProfile(captureAny())).captured.last as User;

  MockApiService echoingApi() {
    final api = MockApiService();
    when(() => api.updateProfile(any())).thenAnswer(
      (call) async => User.fromJson({
        ...(call.positionalArguments.single as User).toJson(),
        'token': 'tok',
      }),
    );
    return api;
  }

  testWidgets('fills the form from the signed-in user', (tester) async {
    await tester.pumpApp(const MeScreen(), size: desktopSize);
    expect(find.text('AP'), findsOneWidget); // initials
    expect(find.text('demo'), findsWidgets);
    expect(
      tester.widget<TextFormField>(field('First Name')).controller!.text,
      'Avery',
    );
    // Both address sections start expanded.
    expect(find.text('120 W 11th St'), findsOneWidget);
  });

  testWidgets('uses the first letter of the username without a name', (
    tester,
  ) async {
    await tester.pumpApp(
      const MeScreen(),
      authState: AuthAuthenticated(user: minimalUser),
    );
    expect(find.text('N'), findsOneWidget);
  });

  testWidgets('saves names and keeps coordinates for unchanged addresses', (
    tester,
  ) async {
    final api = echoingApi();
    await tester.pumpApp(const MeScreen(), api: api, size: desktopSize);
    await tester.enterText(field('First Name'), '  Avery J ');
    await save(tester);

    final sent = sentUser(api);
    expect(sent.firstName, 'Avery J');
    expect(sent.homeLat, demoUser.homeLat);
    expect(sent.workLng, demoUser.workLng);
    expect(find.text('Profile saved successfully!'), findsOneWidget);
  });

  testWidgets('drops stale coordinates when an address changes', (
    tester,
  ) async {
    final api = echoingApi();
    await tester.pumpApp(const MeScreen(), api: api, size: desktopSize);
    // Both address sections start expanded.
    await tester.enterText(field('City').first, 'Brooklyn');
    await save(tester);

    final sent = sentUser(api);
    expect(sent.homeCity, 'Brooklyn');
    expect(sent.homeLat, isNull, reason: 'lets the server geocode it');
    expect(sent.homeLng, isNull);
    expect(sent.workLat, demoUser.workLat, reason: 'work is unchanged');
  });

  testWidgets('shows a failed save', (tester) async {
    final api = MockApiService();
    when(
      () => api.updateProfile(any()),
    ).thenThrow(ApiException('Failed to update profile: 500'));
    await tester.pumpApp(const MeScreen(), api: api, size: desktopSize);
    await save(tester);
    expect(
      find.text('Exception: Failed to update profile: 500'),
      findsOneWidget,
    );
  });

  testWidgets('logout signs out', (tester) async {
    await tester.pumpApp(const MeScreen(), size: desktopSize);
    final context = tester.element(find.byType(MeScreen));
    await tester.ensureVisible(find.text('Logout'));
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(context.read<AuthBloc>().state, isA<AuthUnauthenticated>());
  });

  testWidgets('the standalone screen links to settings', (tester) async {
    FakeGeolocator.install(addTearDown);
    await tester.pumpApp(const MeScreen(), size: desktopSize);
    expect(find.text('My Profile'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('embedded, it has no app bar', (tester) async {
    await tester.pumpApp(
      const Scaffold(body: MeScreen(embedded: true)),
      size: desktopSize,
    );
    expect(find.text('My Profile'), findsNothing);
    expect(find.text('Save Profile'), findsOneWidget);
  });

  testWidgets('shows a spinner while signed out', (tester) async {
    await tester.pumpApp(const MeScreen(), authState: AuthUnauthenticated());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
