import 'package:flutter/material.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/screens/auth/forgot_password_screen.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../support/route_harness.dart';

bool _failKnob(BuildContext context) => context.knobs.boolean(
  label: 'Request fails',
  description: 'Submitting surfaces the AuthFailure snackbar.',
);

@widgetbook.UseCase(name: 'Default', type: LoginScreen)
Widget buildLoginScreenUseCase(BuildContext context) {
  return MockAppScope(
    authState: AuthUnauthenticated(),
    apiFails: _failKnob(context),
    child: const LoginScreen(),
  );
}

@widgetbook.UseCase(name: 'Signing in', type: LoginScreen)
Widget buildLoginScreenLoadingUseCase(BuildContext context) {
  return MockAppScope(authState: AuthLoading(), child: const LoginScreen());
}

@widgetbook.UseCase(name: 'Default', type: RegisterScreen)
Widget buildRegisterScreenUseCase(BuildContext context) {
  // Pushed from LoginScreen in the app, so it gets a real back stack.
  return MockAppScope(
    authState: AuthUnauthenticated(),
    apiFails: _failKnob(context),
    child: RouteHarness(builder: (_) => const RegisterScreen()),
  );
}

@widgetbook.UseCase(name: 'Creating account', type: RegisterScreen)
Widget buildRegisterScreenLoadingUseCase(BuildContext context) {
  return MockAppScope(
    authState: AuthLoading(),
    child: RouteHarness(builder: (_) => const RegisterScreen()),
  );
}

@widgetbook.UseCase(name: 'Default', type: ForgotPasswordScreen)
Widget buildForgotPasswordScreenUseCase(BuildContext context) {
  return MockAppScope(
    authState: AuthUnauthenticated(),
    child: RouteHarness(builder: (_) => const ForgotPasswordScreen()),
  );
}
