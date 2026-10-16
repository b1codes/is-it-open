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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (context) => ApiService()),
        RepositoryProvider(create: (context) => IcalParserService()),
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
