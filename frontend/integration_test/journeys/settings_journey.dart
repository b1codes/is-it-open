import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/side_menu.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/profile/settings_screen.dart';

import '../helpers/e2e.dart';

extension on WidgetTester {
  ThemeMode get themeMode =>
      widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

  Brightness get brightness =>
      Theme.of(element(find.byType(HomeScreen))).brightness;

  SwitchListTile switchTile(String title) =>
      widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));
}

/// Device preferences survive a restart.
void settingsJourneys() {
  journey('the theme and the 24-hour clock persist across a restart', (
    tester,
  ) async {
    final user = await BackendApi().register('settings');
    await storeSession(user);
    await tester.launchApp();
    await tester.waitFor(find.byType(HomeScreen));
    if (!tester.isDesktopLayout) {
      markTestSkipped(
        'Settings and the theme switch are only in the desktop side menu '
        '(github.com/b1codes/is-it-open/issues/43)',
      );
      return;
    }

    // Flip the theme away from whatever the system gives.
    final wanted = tester.brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await tester.tapAndSettle(
      find.descendant(of: find.byType(SideMenu), matching: find.byType(Switch)),
    );
    expect(tester.themeMode, wanted);

    await tester.tapAndSettle(find.text('Settings'));
    await tester.waitFor(find.byType(SettingsScreen));
    expect(tester.switchTile('Use 24-Hour Time').value, isFalse);
    await tester.tapAndSettle(find.text('Use 24-Hour Time'));
    expect(tester.switchTile('Use 24-Hour Time').value, isTrue);

    await tester.relaunchApp();
    await tester.waitFor(find.byType(HomeScreen));
    await tester.settle();
    expect(tester.themeMode, wanted);
    await tester.tapAndSettle(find.text('Settings'));
    await tester.waitFor(find.byType(SettingsScreen));
    expect(tester.switchTile('Use 24-Hour Time').value, isTrue);
  });
}
