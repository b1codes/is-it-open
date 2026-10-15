import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_workspace/main.dart';
import 'package:widgetbook_workspace/main.directories.g.dart';

// Renders every generated use case in preview mode and fails on any build,
// layout or async error, so a broken use case (or a component change that
// breaks one) is caught in CI rather than in the catalog.
//
// RenderFlex overflows are ignored: flutter_test renders text in a font whose
// glyphs are full em squares, far wider than the app's fonts, so overflow
// here does not predict overflow on device. Check those visually with the
// Viewport and TextScale addons instead.

bool _isTestFontOverflow(FlutterErrorDetails details) =>
    details.exceptionAsString().contains('A RenderFlex overflowed');

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
  setUpAll(tz.initializeTimeZones);

  final paths = _useCasePaths(directories).toList();

  test('catalog is not empty', () => expect(paths, isNotEmpty));

  for (final path in paths) {
    testWidgets('renders $path', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final reportError = FlutterError.onError!;
      FlutterError.onError = (details) {
        if (!_isTestFontOverflow(details)) reportError(details);
      };

      final route = Uri(
        path: '/',
        queryParameters: {'path': path, 'preview': ''},
      ).toString();
      try {
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
      } finally {
        // The test binding requires onError to be restored by the body.
        FlutterError.onError = reportError;
      }
    });
  }
}
