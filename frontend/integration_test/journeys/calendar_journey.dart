import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/home/home_screen.dart';

import '../helpers/e2e.dart';

/// A calendar subscription is fetched through the backend's /calendar/proxy
/// and drawn in the calendar.
///
/// The subscription is saved on the account through the API: the app's
/// controls for adding one (and for picking places to plan around) are in the
/// calendar sidebar, which the app doesn't show yet
/// (github.com/b1codes/is-it-open/issues/44).
void calendarJourneys() {
  journey('a saved iCal subscription syncs through the proxy at sign-in and '
      'its events show in the calendar', (tester) async {
    final api = BackendApi();
    final user = await api.register('calendar');
    await api.updateProfile(user, {
      'calendar_subscription_url': stubCalendarUrl,
    });

    await tester.launchApp();
    await tester.signIn(user.username, user.password);
    await tester.waitFor(find.byType(HomeScreen));
    await tester.openTab('Calendar');

    // The stub has one event a day from yesterday to tomorrow (UTC), so at
    // least one falls in this week whatever the time zone.
    await tester.waitFor(find.text(stubEventTitle));
  });
}
