import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// The host side of `flutter drive` (used for the web runs; see e2e/README.md).
// Saves the screenshots journeys take when they fail to build/e2e-screenshots.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/e2e-screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
