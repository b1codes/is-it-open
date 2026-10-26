import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timezone/data/latest.dart' as tz;

// Runs before every test file (see package:flutter_test's flutter_test_config).
//
// flutter_test renders text in its FlutterTest font, whose glyphs are full em
// squares and far wider than any real font, which makes nearly every label
// overflow and every golden meaningless. So real fonts are loaded first:
//
// - Montserrat and Open Sans, the app's Google Fonts, from
//   assets/google_fonts/ (tool/fetch_fonts.sh). Runtime fetching is off, so
//   google_fonts finds them in the asset bundle exactly as it would in an app
//   that bundles them. Building the app themes requests every variant they
//   use; one that isn't bundled fails here, before any test runs.
// - Roboto, the platform sans that unstyled text and the places surface
//   (PlacesType) fall back to, from the Flutter SDK.
// - The bundle's declared font families (FontManifest.json), as an app
//   loads them at startup: Material Icons and Cupertino Icons. flutter_test
//   doesn't, so every icon would draw as an empty box.
//
// PlacesType's serif display styles name platform serifs (New York, Georgia,
// ...) that aren't available here, so they render in Roboto.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Calendar and planner widgets resolve "now" through tz.local.
  tz.initializeTimeZones();
  GoogleFonts.config.allowRuntimeFetching = false;
  AppTheme.lightTheme;
  AppTheme.darkTheme;
  await GoogleFonts.pendingFonts();
  await _loadRoboto();
  await _loadFontManifest();
  await testMain();
}

const _robotoFaces = [
  'Thin',
  'ThinItalic',
  'Light',
  'LightItalic',
  'Regular',
  'Italic',
  'Medium',
  'MediumItalic',
  'Bold',
  'BoldItalic',
  'Black',
  'BlackItalic',
];

Future<void> _loadRoboto() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT is not set; run with `flutter test`.');
  }
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  for (final face in _robotoFaces) {
    final bytes = await File('$dir/Roboto-$face.ttf').readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _loadFontManifest() async {
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
