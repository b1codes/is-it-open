import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';
import 'auth_event.dart';
import 'auth_state.dart';

export 'auth_event.dart';
export 'auth_state.dart';

// Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiService apiClient;

  AuthBloc({required this.apiClient}) : super(AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<LoginRequested>(_onLoginRequested);
    on<RegisterRequested>(_onRegisterRequested);
    on<Auth0LoginRequested>(_onAuth0LoginRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<ProfileUpdateRequested>(_onProfileUpdateRequested);
  }

  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userJsonString = prefs.getString('auth_user_json');
      final username = prefs.getString('auth_username');
      final userId = prefs.getInt('auth_user_id');
      final userEmail = prefs.getString('auth_user_email');
      final calendarUrl = prefs.getString('auth_calendar_url');

      if (token != null) {
        apiClient.setAuthToken(token);
        try {
          final user = await apiClient.getProfile();
          await _saveUser(user);
          emit(AuthAuthenticated(user: user));
        } catch (e) {
          if (userJsonString != null) {
            try {
              final decoded =
                  jsonDecode(userJsonString) as Map<String, dynamic>;
              emit(AuthAuthenticated(user: User.fromJson(decoded)));
            } catch (e2) {
              emit(AuthUnauthenticated());
            }
          } else if (username != null && userId != null) {
            emit(
              AuthAuthenticated(
                user: User(
                  id: userId,
                  username: username,
                  email: userEmail,
                  calendarSubscriptionUrl: calendarUrl,
                  token: token,
                ),
              ),
            );
          } else {
            emit(AuthUnauthenticated());
          }
        }
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await apiClient.login(event.username, event.password);
      apiClient.setAuthToken(user.token);
      await _saveUser(user);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(AuthFailure(error: e.toString()));
    }
  }

  Future<void> _onRegisterRequested(
    RegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await apiClient.register(
        event.username,
        event.password,
        email: event.email,
      );
      apiClient.setAuthToken(user.token);
      await _saveUser(user);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(AuthFailure(error: e.toString()));
    }
  }

  Future<void> _onAuth0LoginRequested(
    Auth0LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      apiClient.setAuthToken(event.token);
      final user = await apiClient.getProfile();
      await _saveUser(user);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(AuthFailure(error: e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    apiClient.setAuthToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_username');
    await prefs.remove('auth_user_id');
    await prefs.remove('auth_user_email');
    emit(AuthUnauthenticated());
  }

  Future<void> _onProfileUpdateRequested(
    ProfileUpdateRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Only update if currently authenticated
    if (state is AuthAuthenticated) {
      final currentState = state as AuthAuthenticated;
      emit(AuthLoading());
      try {
        final user = await apiClient.updateProfile(event.updatedUser);
        // Ensure token is persisted if it wasn't returned in the update
        final updatedUserWithToken = user.token != null
            ? user
            : User(
                id: user.id,
                username: user.username,
                email: user.email,
                firstName: user.firstName,
                lastName: user.lastName,
                homeAddress: user.homeAddress,
                homeLat: user.homeLat,
                homeLng: user.homeLng,
                workAddress: user.workAddress,
                workLat: user.workLat,
                workLng: user.workLng,
                useCurrentLocation: user.useCurrentLocation,
                calendarSubscriptionUrl: user.calendarSubscriptionUrl,
                token: currentState.user.token,
              );

        await _saveUser(updatedUserWithToken);
        emit(ProfileUpdateSuccess(user: updatedUserWithToken));
      } catch (e) {
        // Emit ProfileUpdateFailure which extends AuthAuthenticated
        emit(
          ProfileUpdateFailure(user: currentState.user, error: e.toString()),
        );
      }
    }
  }

  Future<void> _saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    if (user.token != null) await prefs.setString('auth_token', user.token!);
    await prefs.setString('auth_user_json', jsonEncode(user.toJson()));
    await prefs.setString('auth_username', user.username);
    await prefs.setInt('auth_user_id', user.id);
    if (user.email != null) {
      await prefs.setString('auth_user_email', user.email!);
    }
    if (user.calendarSubscriptionUrl != null) {
      await prefs.setString('auth_calendar_url', user.calendarSubscriptionUrl!);
    } else {
      await prefs.remove('auth_calendar_url');
    }
  }
}
