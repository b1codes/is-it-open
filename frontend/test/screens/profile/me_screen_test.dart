import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/profile/settings_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_http_adapter.dart';
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

  Map<String, dynamic> sentFields(MockApiService api) =>
      verify(() => api.updateProfileFields(captureAny())).captured.last
          as Map<String, dynamic>;

  MockApiService echoingApi() {
    final api = MockApiService();
    when(() => api.updateProfileFields(any())).thenAnswer(
      (call) async => User.fromJson({
        ...demoUser.toJson(),
        ...call.positionalArguments.single as Map<String, dynamic>,
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

  // The initials took the first UTF-16 code unit of each name, half of an
  // emoji's surrogate pair, which can't be laid out (found by the edge-case
  // tests for the monkey testing task).
  for (final (first, last, username, initials) in [
    ('😀Avery', 'Ünal', 'demo', '😀Ü'),
    ('👍🏽Avery', '🇨🇦Park', 'demo', '👍🏽🇨🇦'),
    (null, null, '東京tower', '東'),
    (null, null, '👨‍👩‍👧‍👦fam', '👨‍👩‍👧‍👦'),
  ]) {
    testWidgets('initials of ${first ?? username} keep whole characters', (
      tester,
    ) async {
      await tester.pumpApp(
        const MeScreen(),
        authState: AuthAuthenticated(
          user: User(
            id: 9,
            username: username,
            firstName: first,
            lastName: last,
            token: 'tok',
          ),
        ),
      );
      expect(find.text(initials), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saves only the fields that changed, trimmed', (tester) async {
    final api = echoingApi();
    await tester.pumpApp(const MeScreen(), api: api, size: desktopSize);
    await tester.enterText(field('First Name'), '  Avery J ');
    await tester.enterText(field('Last Name'), '');
    await save(tester);

    expect(sentFields(api), {'first_name': 'Avery J', 'last_name': ''});
    expect(find.text('Profile saved successfully!'), findsOneWidget);
  });

  testWidgets('sends an edited address without coordinates', (tester) async {
    final api = echoingApi();
    await tester.pumpApp(const MeScreen(), api: api, size: desktopSize);
    // Both address sections start expanded.
    await tester.enterText(field('City').first, 'Brooklyn');
    await save(tester);

    // The server geocodes it, and keeps the work address's coordinates.
    expect(sentFields(api), {'home_city': 'Brooklyn'});
  });

  testWidgets("doesn't resend what the form didn't change", (tester) async {
    // This device's cached profile predates another device turning on "Use
    // Current Location" (and maybe re-geocoding home). A name change here
    // mustn't send the stale switch or coordinates, which the server takes
    // as explicit changes.
    final http = FakeHttpAdapter()
      ..on(
        'PUT',
        '/auth/me',
        FakeResponse(200, {...demoUser.toJson(), 'first_name': 'Avery J'}),
      );
    await tester.pumpApp(
      const MeScreen(),
      api: ApiService(httpClientAdapter: http),
      size: desktopSize,
    );
    await tester.enterText(field('First Name'), 'Avery J');
    // Quiet Dio's request log; restored before the test ends, as
    // flutter_test checks.
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      await save(tester);
    } finally {
      debugPrint = originalDebugPrint;
    }

    final puts = http.requests.where((r) => r.method == 'PUT');
    expect(puts.single.data, {'first_name': 'Avery J'});
  });

  testWidgets('the save button shows a spinner while saving', (tester) async {
    final reply = Completer<User>();
    final api = MockApiService();
    when(() => api.updateProfileFields(any())).thenAnswer((_) => reply.future);
    await tester.pumpApp(const MeScreen(), api: api, size: desktopSize);
    await tester.ensureVisible(find.text('Save Profile'));
    await tester.tap(find.text('Save Profile'));
    // Not pumpAndSettle: the spinner never settles.
    await tester.pump();

    final button = find.widgetWithText(ElevatedButton, 'Save Profile');
    expect(button, findsNothing);
    expect(
      find.descendant(
        of: find.byType(ElevatedButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    reply.complete(demoUser);
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    expect(find.text('Profile saved successfully!'), findsOneWidget);
  });

  testWidgets('shows a failed save', (tester) async {
    final api = MockApiService();
    when(
      () => api.updateProfileFields(any()),
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
