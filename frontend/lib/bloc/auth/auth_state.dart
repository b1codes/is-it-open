import 'package:equatable/equatable.dart';
import '../../models/user.dart';

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

/// A profile save is in flight. Still signed in as [user] (the profile from
/// before the save), so listeners that compare the previous and current
/// state don't mistake the save for a sign-in or a sign-out.
class ProfileUpdating extends AuthAuthenticated {
  const ProfileUpdating({required super.user});
}

class ProfileUpdateSuccess extends AuthAuthenticated {
  const ProfileUpdateSuccess({required super.user});
}

class ProfileUpdateFailure extends AuthAuthenticated {
  final String error;

  const ProfileUpdateFailure({required super.user, required this.error});

  @override
  List<Object?> get props => [user, error];
}

class AuthUnauthenticated extends AuthState {}

/// The stored session's token was rejected at startup, so the user is
/// signed out without having been [AuthAuthenticated] first. Listeners that
/// clean up after a sign-out need this to tell it from a fresh launch.
class AuthSessionExpired extends AuthUnauthenticated {}

class AuthFailure extends AuthState {
  final String error;

  const AuthFailure({required this.error});

  @override
  List<Object?> get props => [error];
}
