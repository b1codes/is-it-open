import 'package:equatable/equatable.dart';
import '../../models/user.dart';

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

class Auth0LoginRequested extends AuthEvent {
  final String token;

  const Auth0LoginRequested({required this.token});

  @override
  List<Object?> get props => [token];
}
