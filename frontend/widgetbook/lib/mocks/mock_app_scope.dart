import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/bloc/preferences/preferences_cubit.dart';
import 'package:frontend/bloc/search/search_bloc.dart';
import 'package:frontend/bloc/theme/theme_cubit.dart';
import 'package:frontend/bloc/today/today_cubit.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/ical_parser_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_service.dart';
import 'sample_data.dart';
import 'seeded_blocs.dart';

/// Provides the repositories and blocs that `MyApp` wires up in production,
/// backed by [FakeApiService] and seeded with fixture state.
///
/// Changing any argument rebuilds the whole scope from scratch, so knob
/// changes in a use case always start from a clean, deterministic state.
class MockAppScope extends StatelessWidget {
  const MockAppScope({
    super.key,
    required this.child,
    this.authState,
    this.calendarData,
    this.bookmarks,
    this.use24HourFormat = false,
    this.todayRouteIds = const [],
    this.apiFails = false,
    this.apiLatency = const Duration(milliseconds: 300),
  });

  final Widget child;

  /// Defaults to signed in as [demoUser].
  final AuthState? authState;

  /// Defaults to [bookmarks] loaded with the first two places checked and
  /// this week's sample events imported.
  final CalendarDataState? calendarData;

  /// Saved places served by the fake API. Defaults to [sampleSavedPlaces].
  final List<SavedPlace>? bookmarks;

  final bool use24HourFormat;

  /// Tomtom ids pre-loaded into today's route.
  final List<String> todayRouteIds;

  final bool apiFails;

  /// Null keeps every request pending (loading states).
  final Duration? apiLatency;

  @override
  Widget build(BuildContext context) {
    final signature = Object.hash(
      authState,
      calendarData,
      bookmarks == null ? null : Object.hashAll(bookmarks!.map(_bookmarkHash)),
      use24HourFormat,
      Object.hashAll(todayRouteIds),
      apiFails,
      apiLatency,
    );
    return _MockAppScopeHost(key: ValueKey(signature), config: this);
  }

  // SavedPlace has no value equality, so hash every field the fake API
  // serves; a knob that only flips e.g. isPinned must still rebuild.
  static int _bookmarkHash(SavedPlace b) => Object.hash(
    b.id,
    b.place, // Equatable
    b.customName,
    b.icon,
    b.color,
    b.isPinned,
    b.isCheckItOut,
    b.averageVisitLength,
  );
}

class _MockAppScopeHost extends StatefulWidget {
  const _MockAppScopeHost({super.key, required this.config});

  final MockAppScope config;

  @override
  State<_MockAppScopeHost> createState() => _MockAppScopeHostState();
}

class _MockAppScopeHostState extends State<_MockAppScopeHost> {
  late final FakeApiService _api;
  late final IcalParserService _ical;
  late final SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _ensureGlobalPrefsMocked();

    // PreferencesCubit and TodayRouteCubit get a store owned by this scope.
    // A process-global reset here would race the previous scope's cubits,
    // whose in-flight writes could land in this scope's fixture state.
    _prefs = _ScopedPreferences({
      PreferencesCubit.timeFormatKey: config.use24HourFormat,
      if (config.todayRouteIds.isNotEmpty)
        ...TodayRouteCubit.persistedValues(
          config.todayRouteIds,
          DateTime.now(),
        ),
    });

    _api = FakeApiService(
      bookmarks: config.bookmarks,
      fail: config.apiFails,
      latency: config.apiLatency,
    );
    _ical = IcalParserService();
  }

  static bool _globalPrefsMocked = false;

  /// Other blocs still call [SharedPreferences.getInstance]. Back that with
  /// an in-memory store once per process so the catalog never touches real
  /// device storage. It is never reset afterwards, so no scope can clobber
  /// another's writes mid-flight.
  static void _ensureGlobalPrefsMocked() {
    if (_globalPrefsMocked) return;
    _globalPrefsMocked = true;
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  }

  CalendarDataState _defaultCalendarData() {
    final places = widget.config.bookmarks ?? sampleSavedPlaces;
    return CalendarDataState(
      status: CalendarDataStatus.loaded,
      savedPlaces: places,
      checkedPlaceIds: places.take(2).map((sp) => sp.place.tomtomId).toSet(),
      importedEvents: currentWeekEvents,
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ApiService>.value(value: _api),
        RepositoryProvider<IcalParserService>.value(value: _ical),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (_) => SeededAuthBloc(
              apiClient: _api,
              seed: config.authState ?? AuthAuthenticated(user: demoUser),
            ),
          ),
          BlocProvider<CalendarDataBloc>(
            create: (_) => SeededCalendarDataBloc(
              apiService: _api,
              icalParserService: _ical,
              seed: config.calendarData ?? _defaultCalendarData(),
            ),
          ),
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<PreferencesCubit>(
            create: (_) => PreferencesCubit(prefs: _prefs),
          ),
          BlocProvider<TodayRouteCubit>(
            create: (_) => TodayRouteCubit(prefs: _prefs),
          ),
          BlocProvider<SearchBloc>(create: (_) => SearchBloc(apiClient: _api)),
        ],
        child: config.child,
      ),
    );
  }
}

/// An in-memory [SharedPreferences] private to one [MockAppScope], so a
/// scope's cubits read only its seeded values and their writes die with it.
class _ScopedPreferences implements SharedPreferences {
  _ScopedPreferences(Map<String, Object> initial) : _values = {...initial};

  final Map<String, Object> _values;

  Future<bool> _set(String key, Object value) async {
    _values[key] = value;
    return true;
  }

  @override
  Set<String> getKeys() => Set.of(_values.keys);
  @override
  Object? get(String key) => _values[key];
  @override
  bool? getBool(String key) => _values[key] as bool?;
  @override
  int? getInt(String key) => _values[key] as int?;
  @override
  double? getDouble(String key) => _values[key] as double?;
  @override
  String? getString(String key) => _values[key] as String?;
  @override
  bool containsKey(String key) => _values.containsKey(key);
  @override
  List<String>? getStringList(String key) =>
      (_values[key] as List<Object?>?)?.cast<String>().toList();

  @override
  Future<bool> setBool(String key, bool value) => _set(key, value);
  @override
  Future<bool> setInt(String key, int value) => _set(key, value);
  @override
  Future<bool> setDouble(String key, double value) => _set(key, value);
  @override
  Future<bool> setString(String key, String value) => _set(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _set(key, List<String>.of(value));

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _values.clear();
    return true;
  }

  @override
  Future<bool> commit() async => true;
  @override
  Future<void> reload() async {}
}
