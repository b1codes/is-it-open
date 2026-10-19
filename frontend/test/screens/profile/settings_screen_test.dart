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

  User? sentUser(MockApiService api) {
    final calls = verify(() => api.updateProfile(captureAny())).captured;
    return calls.isEmpty ? null : calls.last as User;
  }

  MockApiService echoingApi() {
    final api = MockApiService();
    when(
      () => api.updateProfile(any()),
    ).thenAnswer((call) async => call.positionalArguments.single as User);
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

    final sent = sentUser(api)!;
    expect(sent.useCurrentLocation, isTrue);
    expect((sent.homeLat, sent.homeLng), (51.5, -0.12));
    expect(sent.homeCity, demoUser.homeCity);
    expect(find.text('Settings saved successfully!'), findsOneWidget);
  });

  testWidgets('turning it off keeps the saved coordinates', (tester) async {
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
    final sent = sentUser(api)!;
    expect(sent.useCurrentLocation, isFalse);
    expect(sent.homeLat, demoUser.homeLat);
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
      verifyNever(() => api.updateProfile(any()));
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
    expect(sentUser(api)!.useCurrentLocation, isTrue);
  });

  testWidgets('shows a failed save', (tester) async {
    FakeGeolocator.install(addTearDown);
    final api = MockApiService();
    when(
      () => api.updateProfile(any()),
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
