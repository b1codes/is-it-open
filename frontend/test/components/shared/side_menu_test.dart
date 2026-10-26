import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/theme/theme_cubit.dart';
import 'package:frontend/components/shared/side_menu.dart';
import 'package:frontend/screens/profile/settings_screen.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

void main() {
  late List<int> selected;

  Future<void> pump(
    WidgetTester tester, {
    int index = 0,
    Size size = desktopSize,
  }) async {
    selected = [];
    await tester.pumpApp(
      Scaffold(
        body: Row(
          children: [
            SideMenu(selectedIndex: index, onIndexChanged: selected.add),
          ],
        ),
      ),
      size: size,
    );
  }

  // A phone on its side gets the side menu (it's over 800 wide), but only
  // 390 high; with large text the menu overflowed (found by the monkey test).
  testWidgets('scrolls when it is too short for large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, size: const Size(844, 390));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Logout'), 100);
    await tester.tap(find.text('Logout'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the actions at the bottom when there is room', (
    tester,
  ) async {
    await pump(tester);
    expect(
      tester.getBottomLeft(find.text('Logout')).dy,
      greaterThan(desktopSize.height - 80),
    );
  });

  testWidgets('lists every destination and reports taps', (tester) async {
    await pump(tester, index: 2);
    for (final (i, label) in [
      'My Places',
      'Calendar',
      'Map',
      'Search',
      'Me',
    ].indexed) {
      await tester.tap(find.text(label));
      expect(selected.last, i);
    }
    expect(selected, [0, 1, 2, 3, 4]);
  });

  testWidgets('highlights the selected destination', (tester) async {
    await pump(tester, index: 1);
    await tester.pumpAndSettle();
    Color? iconColor(IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color;
    expect(
      iconColor(Icons.calendar_month_rounded),
      isNot(iconColor(Icons.star_rounded)),
    );
  });

  testWidgets('the switch toggles dark mode', (tester) async {
    await pump(tester);
    final context = tester.element(find.byType(SideMenu));
    expect(find.text('Light Mode'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(context.read<ThemeCubit>().state, ThemeMode.dark);
    expect(find.text('Dark Mode'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(context.read<ThemeCubit>().state, ThemeMode.light);
  });

  testWidgets('logout signs out', (tester) async {
    await pump(tester);
    final context = tester.element(find.byType(SideMenu));
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(context.read<AuthBloc>().state, isA<AuthUnauthenticated>());
  });

  testWidgets('settings opens the settings screen', (tester) async {
    FakeGeolocator.install(addTearDown);
    await pump(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.unmount();
  });
}
