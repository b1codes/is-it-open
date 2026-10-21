import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'screens/home/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'bloc/auth/auth_bloc.dart';
import 'bloc/theme/theme_cubit.dart';
import 'bloc/preferences/preferences_cubit.dart';
import 'bloc/today/today_cubit.dart';
import 'bloc/calendar/calendar_data_bloc.dart';
import 'bloc/calendar/calendar_data_event.dart';
import 'core/env_config.dart';
import 'services/api_service.dart';
import 'services/ical_parser_service.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await EnvConfig.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  /// [apiService] and [icalParserService] default to the real ones; tests
  /// pass fakes to run the whole app without a backend.
  const MyApp({super.key, this.apiService, this.icalParserService});

  final ApiService? apiService;
  final IcalParserService? icalParserService;

  static final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (context) => apiService ?? ApiService()),
        RepositoryProvider(
          create: (context) => icalParserService ?? IcalParserService(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) =>
                AuthBloc(apiClient: context.read<ApiService>())
                  ..add(AppStarted()),
          ),
          BlocProvider<CalendarDataBloc>(
            create: (context) =>
                CalendarDataBloc(
                    apiService: context.read<ApiService>(),
                    icalParserService: context.read<IcalParserService>(),
                  )
                  ..add(LoadSavedPlaces())
                  ..add(const InitDeviceCalendar()),
          ),
          BlocProvider<ThemeCubit>(create: (context) => ThemeCubit()),
          BlocProvider<PreferencesCubit>(
            create: (context) => PreferencesCubit(),
          ),
          BlocProvider<TodayRouteCubit>(create: (context) => TodayRouteCubit()),
        ],
        // Runs on sign-in (into an authenticated state from any other) and
        // on sign-out (out of an authenticated state). A profile save goes
        // ProfileUpdating -> ProfileUpdateSuccess/Failure, all authenticated,
        // so it triggers neither: pushed screens stay open and nothing is
        // reloaded.
        child: BlocListener<AuthBloc, AuthState>(
          listenWhen: (previous, current) {
            bool login =
                current is AuthAuthenticated && previous is! AuthAuthenticated;
            bool logout =
                (current is AuthUnauthenticated || current is AuthFailure) &&
                (previous is AuthAuthenticated);
            return login || logout;
          },
          listener: (context, state) {
            // Home shows login or the app depending on the auth state, so
            // drop any screens pushed on top of it (register, settings, a
            // place) when the user signs in or out. Signing in loads that
            // user's places and calendar; signing out clears them, so the
            // next person on this device doesn't see them.
            _navigatorKey.currentState?.popUntil((route) => route.isFirst);
            if (state is AuthAuthenticated) {
              context.read<CalendarDataBloc>().add(LoadSavedPlaces());
              final url = state.user.calendarSubscriptionUrl;
              if (url != null && url.isNotEmpty) {
                context.read<CalendarDataBloc>().add(LoadRemoteEvents(url));
              }
            } else if (state is AuthUnauthenticated || state is AuthFailure) {
              context.read<CalendarDataBloc>().add(ClearCalendarData());
            }
          },
          child: BlocBuilder<ThemeCubit, ThemeMode>(
            builder: (context, themeMode) {
              return MaterialApp(
                navigatorKey: _navigatorKey,
                title: 'Is It Open',
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeMode,
                home: BlocBuilder<AuthBloc, AuthState>(
                  buildWhen: (previous, current) {
                    if (current is AuthInitial) return true;
                    if (current is AuthLoading) return false;
                    if (current is AuthUnauthenticated) return true;

                    bool wasAuth = previous is AuthAuthenticated;
                    bool isAuth = current is AuthAuthenticated;

                    if (wasAuth != isAuth) return true;
                    if (current is AuthFailure) return true;

                    return false;
                  },
                  builder: (context, state) {
                    if (state is AuthAuthenticated) {
                      return const HomeScreen();
                    }
                    if (state is AuthUnauthenticated || state is AuthFailure) {
                      return const LoginScreen();
                    }
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
