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
          if (e is ApiException && e.isUnauthorized) {
            // The token expired or was revoked: signing in from the cache
            // would leave every request failing.
            apiClient.setAuthToken(null);
            await _clearSession(prefs);
            emit(AuthUnauthenticated());
            return;
          }
          // Offline or server trouble: carry on with the cached profile.
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
    // No AuthLoading first: listeners spot a sign-out as authenticated ->
    // unauthenticated, and an in-between state would hide it.
    apiClient.setAuthToken(null);
    await _clearSession(await SharedPreferences.getInstance());
    emit(AuthUnauthenticated());
  }

  /// Forgets the stored session, including the cached profile, so the next
  /// person on this device doesn't see it.
  Future<void> _clearSession(SharedPreferences prefs) async {
    for (final key in const [
      'auth_token',
      'auth_user_json',
      'auth_username',
      'auth_user_id',
      'auth_user_email',
      'auth_calendar_url',
    ]) {
      await prefs.remove(key);
    }
  }

  Future<void> _onProfileUpdateRequested(
    ProfileUpdateRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Only update if currently authenticated
    if (state is AuthAuthenticated) {
      final currentState = state as AuthAuthenticated;
      // Stays authenticated throughout. AuthLoading here made listeners
      // that compare states see a fresh sign-in once the save finished.
      emit(ProfileUpdating(user: currentState.user));
      try {
        final user = await apiClient.updateProfile(event.updatedUser);
        // Keep the current token if the update didn't return one.
        final updatedUserWithToken = user.token != null
            ? user
            : User.fromJson({
                ...user.toJson(),
                'token': currentState.user.token,
              });

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
