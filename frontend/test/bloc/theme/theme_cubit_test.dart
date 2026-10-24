import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/theme/theme_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('follows the system theme by default', () async {
    final cubit = ThemeCubit(prefs: prefs);
    await pumpEventQueue();
    expect(cubit.state, ThemeMode.system);
  });

  blocTest<ThemeCubit, ThemeMode>(
    'toggleTheme goes system -> light -> dark -> light',
    build: () => ThemeCubit(prefs: prefs),
    act: (cubit) => cubit
      ..toggleTheme()
      ..toggleTheme()
      ..toggleTheme(),
    expect: () => [ThemeMode.light, ThemeMode.dark, ThemeMode.light],
  );

  blocTest<ThemeCubit, ThemeMode>(
    'setTheme sets the mode and saves it',
    build: () => ThemeCubit(prefs: prefs),
    act: (cubit) => cubit.setTheme(ThemeMode.dark),
    expect: () => [ThemeMode.dark],
    verify: (_) => expect(prefs.getString(ThemeCubit.themeModeKey), 'dark'),
  );

  for (final mode in ThemeMode.values) {
    blocTest<ThemeCubit, ThemeMode>(
      'a saved ${mode.name} theme is restored on the next start',
      setUp: () => prefs.setString(ThemeCubit.themeModeKey, mode.name),
      build: () => ThemeCubit(prefs: prefs),
      // Restoring the default emits nothing new.
      expect: () => [if (mode != ThemeMode.system) mode],
    );
  }

  blocTest<ThemeCubit, ThemeMode>(
    'an unknown saved value is ignored',
    setUp: () => prefs.setString(ThemeCubit.themeModeKey, 'sepia'),
    build: () => ThemeCubit(prefs: prefs),
    expect: () => <ThemeMode>[],
  );

  blocTest<ThemeCubit, ThemeMode>(
    'a choice made while the saved theme loads wins',
    setUp: () => prefs.setString(ThemeCubit.themeModeKey, 'dark'),
    build: () => ThemeCubit(prefs: prefs),
    act: (cubit) => cubit.setTheme(ThemeMode.light),
    expect: () => [ThemeMode.light],
    verify: (_) => expect(prefs.getString(ThemeCubit.themeModeKey), 'light'),
  );

  test('the app-wide store is used when none is given', () async {
    SharedPreferences.setMockInitialValues({ThemeCubit.themeModeKey: 'dark'});
    final cubit = ThemeCubit();
    await pumpEventQueue();
    expect(cubit.state, ThemeMode.dark);
  });

  group('when the store fails', () {
    // An error escaping the unawaited load or save would fail these tests
    // as an uncaught error, as it would crash past every handler in the app.
    late _BrokenPreferences broken;

    setUp(() {
      broken = _BrokenPreferences();
      when(() => broken.getString(any())).thenThrow(Exception('no plugin'));
      when(
        () => broken.setString(any(), any()),
      ).thenThrow(Exception('no plugin'));
    });

    test('it keeps the default theme', () async {
      final cubit = ThemeCubit(prefs: broken);
      await pumpEventQueue();
      expect(cubit.state, ThemeMode.system);
    });

    test('a chosen theme still applies', () async {
      final cubit = ThemeCubit(prefs: broken);
      // Not awaited, as the menu calls it.
      unawaited(cubit.setTheme(ThemeMode.dark));
      await pumpEventQueue();
      expect(cubit.state, ThemeMode.dark);
    });
  });
}

class _BrokenPreferences extends Mock implements SharedPreferences {}
