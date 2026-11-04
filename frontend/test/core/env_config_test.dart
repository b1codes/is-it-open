import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/env_config.dart';

// EnvConfig is process-wide static state, so the fallback test runs before
// init() loads envs/dev.json in the same isolate.
void main() {
  test('falls back to local defaults before init', () {
    expect(EnvConfig.apiBaseUrl, 'http://localhost:8000/api');
    expect(EnvConfig.auth0Domain, 'is-it-open.us.auth0.com');
    expect(EnvConfig.auth0ClientId, 'mock_client_id');
    expect(EnvConfig.auth0Audience, 'https://is-it-open/api');
    expect(EnvConfig.apiReceiveTimeout, const Duration(seconds: 3));
    expectSlowEndpointTimeouts();
    expect(
      EnvConfig.mapTileUrl(dark: false),
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
    expect(
      EnvConfig.mapTileUrl(dark: true),
      'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    );
  });

  test('reads envs/dev.json after init', () async {
    await EnvConfig.init();
    expect(EnvConfig.auth0Domain, 'b1codes.us.auth0.com');
    expect(EnvConfig.auth0Audience, 'https://api.isitopen.com/');
    expect(EnvConfig.auth0ClientId, isNotEmpty);
    expect(EnvConfig.apiReceiveTimeout, const Duration(seconds: 3));
    expectSlowEndpointTimeouts();
    // Desktop platforms without their own key use the web URL.
    expect(
      EnvConfig.apiBaseUrl,
      Platform.isMacOS
          ? 'http://127.0.0.1:8000/api'
          : anyOf('http://127.0.0.1:8000/api', 'http://10.0.2.2:8000/api'),
    );
  });

  test('envs/e2e.json points the API and map tiles at the E2E stack', () async {
    await EnvConfig.init(env: 'e2e');
    expect(EnvConfig.apiBaseUrl, 'http://127.0.0.1:18000/api');
    expect(EnvConfig.apiReceiveTimeout, const Duration(seconds: 20));
    // Raised for CI, the default is still shorter than the slow endpoints'.
    expectSlowEndpointTimeouts();
    for (final dark in [false, true]) {
      expect(
        EnvConfig.mapTileUrl(dark: dark),
        'http://127.0.0.1:18090/tiles/{z}/{x}/{y}.png',
      );
    }
  });
}

/// The endpoints that wait on another server get their backend-derived
/// bounds, which are never shorter than the default.
void expectSlowEndpointTimeouts() {
  expect(EnvConfig.calendarProxyReceiveTimeout, const Duration(seconds: 100));
  expect(EnvConfig.profileUpdateReceiveTimeout, const Duration(seconds: 40));
  expect(EnvConfig.placeSearchReceiveTimeout, const Duration(seconds: 40));
  for (final timeout in [
    EnvConfig.calendarProxyReceiveTimeout,
    EnvConfig.profileUpdateReceiveTimeout,
    EnvConfig.placeSearchReceiveTimeout,
  ]) {
    expect(timeout, greaterThanOrEqualTo(EnvConfig.apiReceiveTimeout));
  }
}
