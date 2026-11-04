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

  /// How long the API may take to start answering, for endpoints that don't
  /// wait on another server (those have their own, below). envs/e2e.json
  /// raises it: CI runners and the Firestore emulator are slower than
  /// production.
  static Duration get apiReceiveTimeout {
    final seconds = _config?['api_receive_timeout_seconds'];
    return Duration(seconds: seconds is int ? seconds : 3);
  }

  // Endpoints that answer only once another server has (a calendar feed,
  // TomTom) get longer than [apiReceiveTimeout]: cut off at 3 s, they failed
  // in the app while the backend went on to finish, and the app said a
  // profile edit failed that was saved. Each bound is the backend's own limit
  // for that work (see the backend files named), plus up to 10 s for auth
  // when the backend has no Auth0 keys cached yet (2 * JWKS_FETCH_TIMEOUT,
  // backend/apps/users/auth.py), plus a 10 s margin. A requests `timeout=t`
  // allows t to connect and t again for the answer, so a TomTom call can take
  // 2t. Change these with the backend's limits.

  /// GET /calendar/proxy. A fetch has a 30 s deadline that reading the body
  /// can overrun by one 10 s read (DEADLINE and TIMEOUT in
  /// backend/services/safe_fetch.py), and a webcal:// URL can take two: HTTPS,
  /// then HTTP when that server can't be reached (backend/apps/calendar/api.py).
  /// 10 (auth) + 2 * (30 + 10) + 10 (margin).
  static Duration get calendarProxyReceiveTimeout =>
      _atLeastDefault(const Duration(seconds: 100));

  /// PUT /auth/me. A changed home and work address are geocoded one after the
  /// other, each with `timeout=5` (geocode_address in
  /// backend/services/tomtom.py). 10 (auth) + 2 * (5 + 5) + 10 (margin).
  static Duration get profileUpdateReceiveTimeout =>
      _atLeastDefault(const Duration(seconds: 40));

  /// GET /places/search and /places/suggestions, which ask TomTom once with
  /// `timeout=10` (search_place and nearby_search in
  /// backend/services/tomtom.py). 10 (auth) + (10 + 10) + 10 (margin).
  static Duration get placeSearchReceiveTimeout =>
      _atLeastDefault(const Duration(seconds: 40));

  /// [bound], or [apiReceiveTimeout] if that's longer, so a default raised
  /// for a slow environment (envs/e2e.json) applies to these endpoints too.
  static Duration _atLeastDefault(Duration bound) =>
      bound > apiReceiveTimeout ? bound : apiReceiveTimeout;

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
