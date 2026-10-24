import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_bloc.dart';
import 'package:frontend/bloc/calendar/calendar_data_state.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/ical_parser_service.dart';
import 'package:frontend/utils/app_theme.dart';

import 'fixtures.dart';

/// Phone and desktop viewports; most screens switch layout around 900px.
const phoneSize = Size(390, 844);
const desktopSize = Size(1280, 900);

extension PumpApp on WidgetTester {
  /// Pumps [widget] as the home route of a themed [MaterialApp] inside a
  /// [MockAppScope]: every bloc and repository the app provides, backed by
  /// [FakeApiService] (instant responses by default) and seeded with the
  /// shared fixtures. Pass [api] to serve requests from a mock instead; the
  /// auth and calendar-data blocs then use it too (calendar data starts
  /// empty unless [calendarData] is given).
  Future<void> pumpApp(
    Widget widget, {
    Size size = phoneSize,
    AuthState? authState,
    CalendarDataState? calendarData,
    List<SavedPlace>? bookmarks,
    bool use24HourFormat = false,
    List<String> todayRouteIds = const [],
    bool apiFails = false,
    Duration? apiLatency = Duration.zero,
    ApiService? api,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    setViewport(size);
    Widget app = MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: widget,
    );
    // Above the Navigator, so pushed routes and sheets see the override too,
    // along with blocs that call it rather than MockAppScope's FakeApiService.
    if (api != null) {
      app = RepositoryProvider<ApiService>.value(
        value: api,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>(
              create: (_) => SeededAuthBloc(
                apiClient: api,
                seed: authState ?? AuthAuthenticated(user: demoUser),
              ),
            ),
            BlocProvider<CalendarDataBloc>(
              create: (_) => SeededCalendarDataBloc(
                apiService: api,
                icalParserService: IcalParserService(),
                seed: calendarData ?? const CalendarDataState(),
              ),
            ),
          ],
          child: app,
        ),
      );
    }
    await pumpWidget(
      MockAppScope(
        authState: authState,
        calendarData: calendarData,
        bookmarks: bookmarks,
        use24HourFormat: use24HourFormat,
        todayRouteIds: todayRouteIds,
        apiFails: apiFails,
        apiLatency: apiLatency,
        child: app,
      ),
    );
    await pump();
  }

  /// Sizes the test window; reset automatically when the test ends.
  void setViewport(Size size) {
    view.physicalSize = size;
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  }

  /// Unmounts the tree and lets pending fake-API timers and animations drain,
  /// so a test can end without "A Timer is still pending" failures.
  Future<void> unmount() async {
    await pumpWidget(const SizedBox.shrink());
    await pump(const Duration(seconds: 1));
  }
}
