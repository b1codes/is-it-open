import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/monkey.dart';
import 'helpers/e2e.dart';

/// What the monkey must not touch on a device: signing out (it would spend
/// the run on the sign-in screen), and anything that opens a native file
/// picker or permission prompt, which a test can't answer.
const _offLimits = [
  'Logout',
  'Import .ics file',
  'Sync Device Calendars',
  'Use Current Location',
  'Continue with', // Auth0
];

// The monkey (test/monkey/) on a device or simulator, against the E2E stack,
// signed in as an account of its own. Not part of app_test.dart: it runs
// nightly on mobile only (e2e-mobile.yml). Requests take real time here, so
// a seed replays the same actions but not always the same timing.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initApp);
  setUp(resetDevice);

  testWidgets(
    'the monkey, signed in',
    timeout: const Timeout(Duration(minutes: 30)),
    (tester) async {
      final seed = scenarioSeed('device');
      final replay =
          'flutter test integration_test/monkey_test.dart -d <device> '
          '--dart-define=ENV=e2e --dart-define=SEED=$monkeySeed '
          '--dart-define=MONKEY_STEPS=$monkeySteps';
      debugPrint('Monkey on a device: seed $seed. Replay: $replay');

      final user = await BackendApi().register('monkey');
      await storeSession(user);
      await tester.launchApp();
      await tester.waitFor(find.byType(HomeScreen));

      await Monkey(
        tester,
        seed: seed,
        steps: monkeySteps,
        replay: replay,
        onLog: debugPrint,
        avoid: _offLimits,
        // Turning the test's view isn't turning the device; the widget tests
        // cover layout changes.
        weights: {...Monkey.defaultWeights}..remove(MonkeyAction.rotate),
      ).run();
    },
  );
}
