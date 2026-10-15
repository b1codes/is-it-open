import 'package:flutter/material.dart';
import 'package:frontend/utils/app_theme.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import 'main.directories.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Calendar and planner widgets resolve "now" through tz.local.
  tz.initializeTimeZones();
  runApp(const WidgetbookApp());
}

@widgetbook.App()
class WidgetbookApp extends StatelessWidget {
  const WidgetbookApp({super.key, this.initialRoute = '/'});

  /// Deep link such as `/?path=components/places/statuspill/playground`.
  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return Widgetbook.material(
      initialRoute: initialRoute,
      directories: directories,
      addons: [
        MaterialThemeAddon(
          themes: [
            WidgetbookTheme(name: 'Light', data: AppTheme.lightTheme),
            WidgetbookTheme(name: 'Dark', data: AppTheme.darkTheme),
          ],
        ),
        ViewportAddon([
          Viewports.none,
          IosViewports.iPhone13,
          IosViewports.iPhoneSE,
          AndroidViewports.samsungGalaxyS20,
          IosViewports.iPadPro11Inches,
          MacosViewports.macbookPro,
        ]),
        TextScaleAddon(min: 1.0, max: 2.0, divisions: 4),
        ZoomAddon(),
        GridAddon(),
        InspectorAddon(),
        // Experimental from widgetbook 3.24, which CI resolves; local Flutter
        // pins 3.23 where it is stable.
        // ignore: experimental_member_use
        SemanticsAddon(),
      ],
    );
  }
}
