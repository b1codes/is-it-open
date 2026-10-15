import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesState {
  final bool use24HourFormat;

  const PreferencesState({required this.use24HourFormat});

  PreferencesState copyWith({bool? use24HourFormat}) {
    return PreferencesState(
      use24HourFormat: use24HourFormat ?? this.use24HourFormat,
    );
  }
}

class PreferencesCubit extends Cubit<PreferencesState> {
  /// SharedPreferences key holding the 24-hour clock setting.
  static const String timeFormatKey = 'use_24_hour_format';

  /// [prefs] overrides the store preferences are read from and written to.
  /// Defaults to the app-wide [SharedPreferences.getInstance]; pass an
  /// isolated instance to keep fixtures and tests from sharing state.
  PreferencesCubit({SharedPreferences? prefs})
    : _injectedPrefs = prefs,
      super(const PreferencesState(use24HourFormat: false)) {
    _loadPreferences();
  }

  final SharedPreferences? _injectedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  Future<void> _loadPreferences() async {
    final prefs = await _prefs();
    final use24HourFormat = prefs.getBool(timeFormatKey) ?? false;
    emit(state.copyWith(use24HourFormat: use24HourFormat));
  }

  Future<void> toggle24HourFormat(bool value) async {
    final prefs = await _prefs();
    await prefs.setBool(timeFormatKey, value);
    emit(state.copyWith(use24HourFormat: value));
  }
}
