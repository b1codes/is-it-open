import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/home/home_screen.dart';

import '../helpers/e2e.dart';
import '../helpers/monkey.dart';

/// Whether app_test.dart runs the monkey after the journeys:
/// `--dart-define=MONKEY=true` (the nightly mobile runs set it).
const runMonkey = bool.fromEnvironment('MONKEY');

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

// The monkey (helpers/monkey.dart) on a device or simulator, against the E2E stack,
// signed in as an account of its own. It runs after the journeys in the same
// app, so a device builds and launches the test app once. Requests take real
// time here, so a seed replays the same actions but not always the same
// timing.
void monkeyJourneys() {
  testWidgets(
    'the monkey, signed in',
    timeout: const Timeout(Duration(minutes: 30)),
    (tester) async {
      final seed = scenarioSeed('device');
      final replay =
          'flutter test integration_test/app_test.dart -d <device> '
          '--dart-define=ENV=e2e --dart-define=MONKEY=true '
          '--dart-define=SEED=$monkeySeed '
          '--dart-define=MONKEY_STEPS=$monkeySteps --plain-name monkey';
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
