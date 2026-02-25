import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AppStarted extends AuthEvent {}

class LoginRequested extends AuthEvent {
  final String username;
  final String password;

  const LoginRequested({required this.username, required this.password});

  @override
  List<Object?> get props => [username, password];
}

class RegisterRequested extends AuthEvent {
  final String username;
  final String password;
  final String? email;

  const RegisterRequested({
    required this.username,
    required this.password,
    this.email,
  });

  @override
  List<Object?> get props => [username, password, email];
}

class LogoutRequested extends AuthEvent {}

class ProfileUpdateRequested extends AuthEvent {
  final User updatedUser;

  const ProfileUpdateRequested({required this.updatedUser});

  @override
  List<Object?> get props => [updatedUser];
}

// States
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;

  const AuthAuthenticated({required this.user});

  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthFailure extends AuthState {
  final String error;

  const AuthFailure({required this.error});

  @override
  List<Object?> get props => [error];
}

// Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiService apiClient;

  AuthBloc({required this.apiClient}) : super(AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<LoginRequested>(_onLoginRequested);
    on<RegisterRequested>(_onRegisterRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<ProfileUpdateRequested>(_onProfileUpdateRequested);
  }

  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final username = prefs.getString('auth_username');
      final userId = prefs.getInt('auth_user_id');
      final userEmail = prefs.getString('auth_user_email');

      if (token != null && username != null && userId != null) {
        apiClient.setAuthToken(token);
        emit(
          AuthAuthenticated(
            user: User(
              id: userId,
              username: username,
              email: userEmail,
              token: token,
            ),
          ),
        );
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
                token: currentState.user.token,
              );

        await _saveUser(updatedUserWithToken);
        emit(AuthAuthenticated(user: updatedUserWithToken));
      } catch (e) {
        // Revert to the authenticated state with old user if it fails
        emit(AuthFailure(error: e.toString()));
        emit(AuthAuthenticated(user: currentState.user));
      }
    }
  }

  Future<void> _saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    if (user.token != null) await prefs.setString('auth_token', user.token!);
    await prefs.setString('auth_username', user.username);
    await prefs.setInt('auth_user_id', user.id);
    if (user.email != null) {
      await prefs.setString('auth_user_email', user.email!);
    }
  }
}
