import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/preferences/preferences_cubit.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/profile/settings_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

void main() {
  setUpAll(registerFallbacks);

  final locationSwitch = find.widgetWithText(
    SwitchListTile,
    'Use Current Location',
  );

  Map<String, dynamic>? sentFields(MockApiService api) {
    final calls = verify(() => api.updateProfileFields(captureAny())).captured;
    return calls.isEmpty ? null : calls.last as Map<String, dynamic>;
  }

  User saved(Map<String, dynamic> fields) =>
      User.fromJson({...demoUser.toJson(), ...fields});

  MockApiService echoingApi() {
    final api = MockApiService();
    when(() => api.updateProfileFields(any())).thenAnswer(
      (call) async =>
          saved(call.positionalArguments.single as Map<String, dynamic>),
    );
    return api;
  }

  testWidgets('turning location on saves the device position', (tester) async {
    FakeGeolocator.install(
      addTearDown,
      FakeGeolocator(position: fakePosition(51.5, -0.12)),
    );
    final api = echoingApi();
    await tester.pumpApp(const SettingsScreen(), api: api);
    await tester.tap(locationSwitch);
    await tester.pumpAndSettle();

    // Only what changed: the rest of the cached profile may be stale.
    expect(sentFields(api), {
      'use_current_location': true,
      'home_lat': 51.5,
      'home_lng': -0.12,
    });
    expect(find.text('Settings saved successfully!'), findsOneWidget);
  });

  testWidgets('turning it off sends only the switch', (tester) async {
    FakeGeolocator.install(addTearDown);
    final api = echoingApi();
    await tester.pumpApp(
      const SettingsScreen(),
      api: api,
      authState: AuthAuthenticated(
        user: User.fromJson({
          ...demoUser.toJson(),
          'use_current_location': true,
        }),
      ),
    );
    await tester.tap(locationSwitch);
    await tester.pumpAndSettle();
    expect(sentFields(api), {'use_current_location': false});
  });

  final refusals = {
    'location services are off': (
      FakeGeolocator(serviceEnabled: false),
      'Location services are disabled.',
    ),
    'permission is denied': (
      FakeGeolocator(permission: LocationPermission.denied),
      'Location permissions are denied',
    ),
    'permission is denied forever': (
      FakeGeolocator(permission: LocationPermission.deniedForever),
      'Location permissions are permanently denied.',
    ),
    'the position cannot be read': (
      FakeGeolocator(positionError: Exception('no fix')),
      'Error getting location: Exception: no fix',
    ),
  };
  for (final MapEntry(key: why, value: (geolocator, message))
      in refusals.entries) {
    testWidgets('explains and saves nothing when $why', (tester) async {
      FakeGeolocator.install(addTearDown, geolocator);
      final api = echoingApi();
      await tester.pumpApp(const SettingsScreen(), api: api);
      await tester.tap(locationSwitch);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      verifyNever(() => api.updateProfileFields(any()));
      expect(
        tester.widget<SwitchListTile>(locationSwitch).onChanged,
        isNotNull,
        reason: 'the switch is usable again',
      );
    });
  }

  testWidgets('asks for permission, then saves if it is granted', (
    tester,
  ) async {
    final geolocator = FakeGeolocator.install(
      addTearDown,
      FakeGeolocator(
        permission: LocationPermission.denied,
        permissionAfterRequest: LocationPermission.whileInUse,
      ),
    );
    final api = echoingApi();
    await tester.pumpApp(const SettingsScreen(), api: api);
    await tester.tap(locationSwitch);
    await tester.pumpAndSettle();
    expect(geolocator.permissionRequests, 1);
    expect(sentFields(api)!['use_current_location'], isTrue);
  });

  testWidgets('shows a spinner and holds the switch while saving', (
    tester,
  ) async {
    FakeGeolocator.install(addTearDown);
    final reply = Completer<User>();
    final api = MockApiService();
    when(() => api.updateProfileFields(any())).thenAnswer((_) => reply.future);
    await tester.pumpApp(const SettingsScreen(), api: api);
    await tester.tap(locationSwitch);
    // Not pumpAndSettle: the spinner never settles.
    await tester.pump();
    await tester.pump();

    final context = tester.element(find.byType(SettingsScreen));
    expect(context.read<AuthBloc>().state, isA<ProfileUpdating>());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<SwitchListTile>(locationSwitch).onChanged, isNull);

    reply.complete(saved(sentFields(api)!));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<SwitchListTile>(locationSwitch).value, isTrue);
    expect(tester.widget<SwitchListTile>(locationSwitch).onChanged, isNotNull);
  });

  testWidgets('shows a failed save', (tester) async {
    FakeGeolocator.install(addTearDown);
    final api = MockApiService();
    when(
      () => api.updateProfileFields(any()),
    ).thenThrow(ApiException('Failed to update profile: 500'));
    await tester.pumpApp(const SettingsScreen(), api: api);
    await tester.tap(locationSwitch);
    await tester.pumpAndSettle();
    expect(
      find.text('Exception: Failed to update profile: 500'),
      findsOneWidget,
    );
  });

  testWidgets('toggles the 24-hour clock', (tester) async {
    await tester.pumpApp(const SettingsScreen());
    final context = tester.element(find.byType(SettingsScreen));
    await tester.tap(find.text('Use 24-Hour Time'));
    await tester.pumpAndSettle();
    expect(context.read<PreferencesCubit>().state.use24HourFormat, isTrue);
  });

  testWidgets('shows a spinner while signed out', (tester) async {
    await tester.pumpApp(
      const SettingsScreen(),
      authState: AuthUnauthenticated(),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
