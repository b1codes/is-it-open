import 'dart:convert';

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
      bookmarks == null ? null : Object.hashAll(bookmarks!.map((b) => b.id)),
      use24HourFormat,
      Object.hashAll(todayRouteIds),
      apiFails,
      apiLatency,
    );
    return _MockAppScopeHost(key: ValueKey(signature), config: this);
  }
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

  @override
  void initState() {
    super.initState();
    final config = widget.config;

    // PreferencesCubit and TodayRouteCubit hydrate from SharedPreferences in
    // their constructors, so seed the in-memory store before they are built.
    // This also keeps the catalog from reading or writing real device
    // storage.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'use_24_hour_format': config.use24HourFormat,
      if (config.todayRouteIds.isNotEmpty) ...{
        'today_route_ids': jsonEncode(config.todayRouteIds),
        'today_route_date': _dateKey(DateTime.now()),
      },
    });

    _api = FakeApiService(
      bookmarks: config.bookmarks,
      fail: config.apiFails,
      latency: config.apiLatency,
    );
    _ical = IcalParserService();
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

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
          BlocProvider<PreferencesCubit>(create: (_) => PreferencesCubit()),
          BlocProvider<TodayRouteCubit>(create: (_) => TodayRouteCubit()),
          BlocProvider<SearchBloc>(create: (_) => SearchBloc(apiClient: _api)),
        ],
        child: config.child,
      ),
    );
  }
}
