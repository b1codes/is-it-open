import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/screens/auth/forgot_password_screen.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';

import '../../helpers/pump_app.dart';

// login_screen.dart, register_screen.dart and forgot_password_screen.dart.
// main_test.dart covers the screens inside the real app's auth routing.
void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  AuthState authState(WidgetTester tester, Type screen) =>
      tester.element(find.byType(screen)).read<AuthBloc>().state;

  group('LoginScreen', () {
    testWidgets('validates the developer login form', (tester) async {
      await tester.pumpApp(
        const LoginScreen(),
        authState: AuthUnauthenticated(),
      );
      await tester.tap(find.text('LOCAL SIGN IN'));
      await tester.pump();
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(authState(tester, LoginScreen), isA<AuthUnauthenticated>());
    });

    testWidgets('signs in with a username and password', (tester) async {
      await tester.pumpApp(
        const LoginScreen(),
        authState: AuthUnauthenticated(),
      );
      await tester.enterText(field('Email Address'), 'demo');
      await tester.enterText(field('Password'), 'secret');
      await tester.tap(find.text('LOCAL SIGN IN'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(authState(tester, LoginScreen), isA<AuthAuthenticated>());
    });

    testWidgets('shows a failed sign-in', (tester) async {
      await tester.pumpApp(
        const LoginScreen(),
        authState: AuthUnauthenticated(),
        apiFails: true,
      );
      await tester.enterText(field('Email Address'), 'demo');
      await tester.enterText(field('Password'), 'wrong');
      await tester.tap(find.text('LOCAL SIGN IN'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('simulated network failure'), findsOneWidget);
    });

    for (final button in [
      'Continue with Google',
      'Continue with Apple',
      'Continue with Email',
    ]) {
      testWidgets('"$button" opens Auth0 and signs in', (tester) async {
        tester.setViewport(const Size(800, 1400));
        await tester.pumpApp(
          const LoginScreen(),
          authState: AuthUnauthenticated(),
          size: const Size(800, 1400),
        );
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        // Complete the mock universal login with its own Google button.
        await tester.tap(find.text('Continue with Google').last);
        await tester.pumpAndSettle();
        expect(authState(tester, LoginScreen), isA<AuthAuthenticated>());
      });
    }

    testWidgets('dismissing Auth0 changes nothing', (tester) async {
      await tester.pumpApp(
        const LoginScreen(),
        authState: AuthUnauthenticated(),
        size: const Size(800, 1400),
      );
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(authState(tester, LoginScreen), isA<AuthUnauthenticated>());
    });

    testWidgets('links to password recovery and sign-up', (tester) async {
      await tester.pumpApp(
        const LoginScreen(),
        authState: AuthUnauthenticated(),
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Join the neighborhood'));
      await tester.tap(find.text('Join the neighborhood'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      // "Sign in" goes back to the login screen underneath.
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets('validates every field', (tester) async {
      await tester.pumpApp(
        const RegisterScreen(),
        authState: AuthUnauthenticated(),
      );
      await tester.tap(find.text('JOIN'));
      await tester.pump();
      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Create a password'), findsOneWidget);
    });

    testWidgets('registers the account', (tester) async {
      await tester.pumpApp(
        const RegisterScreen(),
        authState: AuthUnauthenticated(),
      );
      await tester.enterText(field('Full Name'), 'newcomer');
      await tester.enterText(field('Email Address'), 'n@example.com');
      await tester.enterText(field('Password'), 'secret');
      await tester.tap(find.text('JOIN'));
      await tester.pumpAndSettle();
      final state = authState(tester, RegisterScreen);
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.username, 'newcomer');
    });

    testWidgets('shows a failed registration', (tester) async {
      await tester.pumpApp(
        const RegisterScreen(),
        authState: AuthUnauthenticated(),
        apiFails: true,
      );
      await tester.enterText(field('Full Name'), 'newcomer');
      await tester.enterText(field('Email Address'), 'n@example.com');
      await tester.enterText(field('Password'), 'secret');
      await tester.tap(find.text('JOIN'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('"Sign in" replaces it with login when it is the root', (
      tester,
    ) async {
      await tester.pumpApp(
        const RegisterScreen(),
        authState: AuthUnauthenticated(),
      );
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('ForgotPasswordScreen', () {
    testWidgets('asks for an email, then confirms', (tester) async {
      await tester.pumpApp(const ForgotPasswordScreen());
      await tester.tap(find.text('SEND RESET LINK'));
      await tester.pump();
      expect(find.text('Enter your email'), findsOneWidget);

      await tester.enterText(field('Email Address'), 'avery@example.com');
      await tester.tap(find.text('SEND RESET LINK'));
      await tester.pumpAndSettle();
      expect(find.text('CHECK YOUR EMAIL'), findsOneWidget);
      expect(find.textContaining('avery@example.com'), findsOneWidget);
    });

    testWidgets('"Back to login" pops', (tester) async {
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email Address'), 'a@b.c');
      await tester.tap(find.text('SEND RESET LINK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to login'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsNothing);
    });
  });
}
