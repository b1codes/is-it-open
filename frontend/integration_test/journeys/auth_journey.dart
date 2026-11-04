import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';

import '../helpers/e2e.dart';

/// Register → log out → log in → relaunch, against the real backend.
void authJourneys() {
  journey('a new user registers, logs out, logs back in, and stays '
      'signed in across a relaunch', (tester) async {
    final username = uniqueUsername('signup');
    await tester.launchApp();
    await tester.waitFor(find.byType(LoginScreen));

    await tester.tapAndSettle(find.text('Join the neighborhood'));
    await tester.enterField('Full Name', username);
    await tester.enterField('Email Address', '$username@example.com');
    await tester.enterField('Password', 'correct horse');
    await tester.tapAndSettle(find.text('JOIN'));
    await tester.waitFor(find.byType(HomeScreen));

    await tester.logOut();
    await tester.waitFor(find.byType(LoginScreen));

    await tester.signIn(username, 'correct horse');
    await tester.waitFor(find.byType(HomeScreen));

    await tester.relaunchApp();
    await tester.waitFor(find.byType(HomeScreen));
    expect(find.byType(LoginScreen), findsNothing);
  });

  journey('the seeded user signs in and sees their saved places', (
    tester,
  ) async {
    await tester.launchApp();
    await tester.signIn(seededUsername, seededPassword);
    await tester.waitFor(find.byType(HomeScreen));

    await tester.openTab('My Places');
    await tester.waitFor(find.text("Joe's Pizza"));
    expect(find.text('Riverside Community Garden'), findsWidgets);
  });

  journey('a wrong password is refused with a message', (tester) async {
    await tester.launchApp();
    await tester.signIn(seededUsername, 'not-the-password');

    await tester.waitFor(find.byType(SnackBar));
    expect(find.textContaining('Failed to login'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
