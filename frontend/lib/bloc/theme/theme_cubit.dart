import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  /// SharedPreferences key holding the chosen theme ([ThemeMode.name]).
  static const String themeModeKey = 'theme_mode';

  /// [prefs] overrides the store the theme is read from and written to.
  /// Defaults to the app-wide [SharedPreferences.getInstance]; pass an
  /// isolated instance to keep fixtures and tests from sharing state.
  ThemeCubit({SharedPreferences? prefs})
    : _injectedPrefs = prefs,
      super(ThemeMode.system) {
    _loadTheme();
  }

  final SharedPreferences? _injectedPrefs;

  // Set once the user picks a theme, so a slow load can't undo the choice.
  bool _chosen = false;

  Future<SharedPreferences> _prefs() async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  // Started from the constructor and never awaited, so it mustn't throw.
  Future<void> _loadTheme() async {
    final String? saved;
    try {
      saved = (await _prefs()).getString(themeModeKey);
    } catch (_) {
      // The store can't be read (e.g. the plugin failed): keep the default.
      return;
    }
    final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
    if (mode != null && mode != state && !_chosen && !isClosed) emit(mode);
  }

  Future<void> toggleTheme() =>
      setTheme(state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);

  Future<void> setTheme(ThemeMode mode) async {
    _chosen = true;
    emit(mode);
    // The menu doesn't await this either.
    try {
      await (await _prefs()).setString(themeModeKey, mode.name);
    } catch (_) {
      // Not remembered for the next start, but applied for this one.
    }
  }
}
