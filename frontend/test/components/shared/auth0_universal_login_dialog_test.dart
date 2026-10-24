import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/auth0_universal_login_dialog.dart';

Map<String, dynamic> _claims(String jwt) =>
    jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(jwt.split('.')[1]))),
        )
        as Map<String, dynamic>;

void main() {
  late Future<String?> result;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showDialog<String>(
              context: context,
              builder: (_) => const Auth0UniversalLoginDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('validates the email and password', (tester) async {
    await open(tester);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump();
    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);

    await tester.enterText(field('Email address'), 'not-an-email');
    await tester.enterText(field('Password'), '123');
    await tester.tap(find.text('CONTINUE'));
    await tester.pump();
    expect(find.text('Please enter a valid email'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
  });

  testWidgets('signs in with email and returns a mock token', (tester) async {
    await open(tester);
    await tester.enterText(field('Email address'), ' avery@example.com ');
    await tester.enterText(field('Password'), 'secret1');
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    final claims = _claims((await result)!);
    expect(claims['sub'], startsWith('auth0|mock_email_'));
    expect(claims['email'], 'avery@example.com');
    expect(claims['name'], 'avery');
    expect(claims['email_verified'], isTrue);
  });

  testWidgets('sign-up asks for a name and uses it', (tester) async {
    await open(tester);
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Already have an account?'), findsOneWidget);

    await tester.enterText(field('Email address'), 'avery@example.com');
    await tester.enterText(field('Password'), 'secret1');
    await tester.tap(find.text('SIGN UP'));
    await tester.pump();
    expect(find.text('Please enter your name'), findsOneWidget);

    await tester.enterText(field('Full Name'), 'Avery Park');
    await tester.tap(find.text('SIGN UP'));
    await tester.pumpAndSettle();
    final claims = _claims((await result)!);
    expect(claims['name'], 'Avery Park');
    expect(claims['nickname'], 'averypark');

    // Toggling back hides the name field.
    await open(tester);
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(field('Full Name'), findsNothing);
  });

  testWidgets('Apple sign-in splits the name into given and family', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Continue with Apple'));
    await tester.pumpAndSettle();
    final claims = _claims((await result)!);
    expect(claims['sub'], startsWith('apple|mock_apple_'));
    expect(claims['given_name'], isNotEmpty);
    expect(claims['family_name'], isNotEmpty);
  });
}
