import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timezone/data/latest.dart' as tz;

// Runs before every test file (see package:flutter_test's flutter_test_config).
//
// - Loads the timezone database, as main.dart does at startup. Without it,
//   TZID lookups fail and code silently falls back to the machine's zone.
// - Stops google_fonts from fetching Montserrat/Open Sans over the network
//   and registers Roboto (shipped with the Flutter SDK) under those family
//   names instead. flutter_test's default font draws every glyph as a full
//   em square, which overflows nearly every label; Roboto keeps layouts
//   close to a device. Same approach as the Widgetbook smoke test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  GoogleFonts.config.allowRuntimeFetching = false;
  await _loadFonts();
  await testMain();
}

const _robotoFaces = ['Light', 'Regular', 'Italic', 'Medium', 'Bold', 'Black'];

Iterable<String> _families() sync* {
  yield 'Roboto';
  for (final family in ['Montserrat', 'OpenSans']) {
    yield family;
    for (var weight = 100; weight <= 900; weight += 100) {
      final w = weight == 400 ? '' : '$weight';
      yield '${family}_${w.isEmpty ? 'regular' : w}';
      yield '${family}_${w}italic';
    }
  }
}

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return; // `dart test`: keep the default test font.
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final faces = [
    for (final face in _robotoFaces)
      ByteData.sublistView(await File('$dir/Roboto-$face.ttf').readAsBytes()),
  ];
  for (final family in _families()) {
    final loader = FontLoader(family);
    for (final face in faces) {
      loader.addFont(Future.value(face));
    }
    await loader.load();
  }
}
