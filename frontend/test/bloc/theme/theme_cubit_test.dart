import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/theme/theme_cubit.dart';

void main() {
  test('follows the system theme by default', () {
    expect(ThemeCubit().state, ThemeMode.system);
  });

  blocTest<ThemeCubit, ThemeMode>(
    'toggleTheme goes system -> light -> dark -> light',
    build: ThemeCubit.new,
    act: (cubit) => cubit
      ..toggleTheme()
      ..toggleTheme()
      ..toggleTheme(),
    expect: () => [ThemeMode.light, ThemeMode.dark, ThemeMode.light],
  );

  blocTest<ThemeCubit, ThemeMode>(
    'setTheme sets the mode',
    build: ThemeCubit.new,
    act: (cubit) => cubit.setTheme(ThemeMode.dark),
    expect: () => [ThemeMode.dark],
  );
}
