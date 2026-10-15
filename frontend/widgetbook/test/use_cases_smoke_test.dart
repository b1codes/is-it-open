import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_workspace/main.dart';
import 'package:widgetbook_workspace/main.directories.g.dart';

// Renders every generated use case in preview mode and fails on any build,
// layout or async error, so a broken use case (or a component change that
// breaks one) is caught in CI rather than in the catalog. RenderFlex
// overflows count as errors.
//
// flutter_test renders text in its FlutterTest font, whose glyphs are full em
// squares and far wider than any real font, which makes nearly every label
// overflow. So a real proportional font is loaded first: Roboto, the platform
// sans the places surface uses (PlacesType), from the Flutter SDK so no
// network or checked-in font files are needed.
//
// The app's Google Fonts (Montserrat, Open Sans) are fetched at runtime and
// can't be loaded offline, so Roboto also stands in for them. google_fonts
// names each family per variant ('OpenSans_regular', 'Montserrat_700'), and
// the test engine ignores fontFamilyFallback when the primary family is
// missing, so Roboto is registered under every variant name. Montserrat and
// Open Sans run a little wider than Roboto, so a label sitting right at its
// limit can still overflow on device; check those with the Viewport and
// TextScale addons.

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

/// Family names Roboto is registered under.
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
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT is not set; run with `flutter test`.');
  }
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

/// Use case paths in the slug format WidgetbookNode.path produces.
Iterable<String> _useCasePaths(
  List<WidgetbookNode> nodes, [
  String prefix = '',
]) sync* {
  for (final node in nodes) {
    final path = '$prefix${node.name.replaceAll(' ', '-').toLowerCase()}';
    if (node is WidgetbookUseCase) {
      yield path;
    } else {
      yield* _useCasePaths(node.children ?? const [], '$path/');
    }
  }
}

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await _loadFonts();
  });

  final paths = _useCasePaths(directories).toList();

  test('catalog is not empty', () => expect(paths, isNotEmpty));

  for (final path in paths) {
    testWidgets('renders $path', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final route = Uri(
        path: '/',
        queryParameters: {'path': path, 'preview': ''},
      ).toString();
      await tester.pumpWidget(WidgetbookApp(initialRoute: route));
      // Let fake API responses (300ms) and entry animations land.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      // Guard against a silent pass on Widgetbook's home page when a path
      // fails to resolve.
      final state = tester
          .widget<WidgetbookScope>(find.byType(WidgetbookScope))
          .notifier!;
      expect(state.useCase, isNotNull, reason: 'No use case at $path');

      // Tear down inside the test so pending fake-API timers drain.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
