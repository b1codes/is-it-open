import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'bloc/auth/auth_bloc.dart';
import 'bloc/theme/theme_cubit.dart';
import 'bloc/preferences/preferences_cubit.dart';
import 'core/env_config.dart';
import 'services/api_service.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => ApiService(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) =>
                AuthBloc(apiClient: context.read<ApiService>())
                  ..add(AppStarted()),
          ),
          BlocProvider<ThemeCubit>(create: (context) => ThemeCubit()),
          BlocProvider<PreferencesCubit>(
            create: (context) => PreferencesCubit(),
          ),
        ],
        child: CalendarControllerProvider(
          controller: EventController(),
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
