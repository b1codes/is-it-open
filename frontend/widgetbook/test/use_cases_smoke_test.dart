import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog.dart';

// Renders every generated use case in preview mode and fails on any build,
// layout or async error, so a broken use case (or a component change that
// breaks one) is caught in CI rather than in the catalog. RenderFlex
// overflows count as errors. Text renders in the app's real fonts (see
// flutter_test_config.dart). goldens_test.dart covers how each one looks.

void main() {
  test('catalog is not empty', () => expect(useCasePaths, isNotEmpty));

  for (final path in useCasePaths) {
    testWidgets('renders $path', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpUseCase(tester, path);
      expect(tester.takeException(), isNull);

      await unmountUseCase(tester);
    });
  }
}
