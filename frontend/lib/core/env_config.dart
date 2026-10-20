import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EnvConfig {
  static Map<String, dynamic>? _config;

  /// Loads `envs/<env>.json`. [env] defaults to the `ENV` dart-define
  /// (`--dart-define=ENV=e2e` for the E2E journeys), else `dev`.
  static Future<void> init({
    @visibleForTesting
    String env = const String.fromEnvironment('ENV', defaultValue: 'dev'),
  }) async {
    try {
      final String configString = await rootBundle.loadString('envs/$env.json');
      _config = json.decode(configString) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load env config: $e');
      }
    }
  }

  static String get apiBaseUrl {
    if (_config == null) {
      // Fallback for tests or failed init
      return 'http://localhost:8000/api';
    }

    if (kIsWeb) {
      return _config!['api_base_url_web'] as String;
    } else if (Platform.isAndroid) {
      return _config!['api_base_url_android'] as String;
    } else if (Platform.isIOS) {
      return _config!['api_base_url_ios'] as String;
    } else if (Platform.isMacOS) {
      return _config!['api_base_url_macos'] as String;
    } else {
      // Default to desktop/web logic for other platforms
      return _config!['api_base_url_desktop'] ??
          _config!['api_base_url_web'] as String;
    }
  }

  static String get auth0Domain {
    return _config?['auth0_domain'] as String? ?? 'is-it-open.us.auth0.com';
  }

  static String get auth0ClientId {
    return _config?['auth0_client_id'] as String? ?? 'mock_client_id';
  }

  static String get auth0Audience {
    return _config?['auth0_audience'] as String? ?? 'https://is-it-open/api';
  }

  /// The map's tile URL template. envs/e2e.json points it at the E2E stub's
  /// blank tiles, so the journeys never fetch real tiles.
  static String mapTileUrl({required bool dark}) {
    final configured = _config?[dark ? 'map_tile_url_dark' : 'map_tile_url'];
    if (configured is String) return configured;
    return dark
        ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }
}
