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
  });

  test('reads envs/dev.json after init', () async {
    await EnvConfig.init();
    expect(EnvConfig.auth0Domain, 'b1codes.us.auth0.com');
    expect(EnvConfig.auth0Audience, 'https://api.isitopen.com/');
    expect(EnvConfig.auth0ClientId, isNotEmpty);
    // Desktop platforms without their own key use the web URL.
    expect(
      EnvConfig.apiBaseUrl,
      Platform.isMacOS
          ? 'http://127.0.0.1:8000/api'
          : anyOf('http://127.0.0.1:8000/api', 'http://10.0.2.2:8000/api'),
    );
  });
}
