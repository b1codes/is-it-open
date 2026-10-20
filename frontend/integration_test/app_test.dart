import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e.dart';
import 'journeys/auth_journey.dart';
import 'journeys/calendar_journey.dart';
import 'journeys/places_journey.dart';
import 'journeys/profile_journey.dart';
import 'journeys/settings_journey.dart';

// Every E2E journey, against the stack in docker-compose.e2e.yml. One entry
// point, so the app is built once per run. See e2e/README.md.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initApp);
  setUp(resetDevice);

  group('auth', authJourneys);
  group('profile', profileJourneys);
  group('places', placesJourneys);
  group('settings', settingsJourneys);
  group('calendar', calendarJourneys);
}
