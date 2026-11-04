import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/auth0_universal_login_dialog.dart';
import 'package:frontend/services/auth0_service.dart';

Map<String, dynamic> _claims(String jwt) {
  final payload = jwt.split('.')[1];
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))))
      as Map<String, dynamic>;
}

void main() {
  group('Auth0Service.login', () {
    late Future<String?> result;

    Future<void> openLogin(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = Auth0Service().login(context),
              child: const Text('Log in'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the universal login dialog', (tester) async {
      await openLogin(tester);
      expect(find.byType(Auth0UniversalLoginDialog), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);
    });

    testWidgets('returns the token the dialog signs in with', (tester) async {
      await openLogin(tester);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      final token = await result;
      expect(token, isNotNull);
      final claims = _claims(token!);
      expect(claims['sub'], startsWith('google-oauth2|mock_google-oauth2_'));
      expect(claims['exp'] - claims['iat'], 3600);
      expect(find.byType(Auth0UniversalLoginDialog), findsNothing);
    });

    testWidgets('returns null when the dialog is cancelled', (tester) async {
      await openLogin(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    testWidgets('returns null when the barrier is tapped', (tester) async {
      await openLogin(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });
}
