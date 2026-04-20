import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EnvConfig {
  static Map<String, dynamic>? _config;

  static Future<void> init() async {
    const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
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
}
