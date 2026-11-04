@Tags(['monkey'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';
import '../../integration_test/helpers/monkey.dart';

/// Where each scenario writes its action log, and a screenshot on failure.
const _outDir = 'build/monkey';

/// "Now" for every run, so the screens (open/closed, today's events) and
/// therefore the monkey's targets are the same on every run.
final _now = DateTime(2026, 6, 10, 10, 30);

class _Scenario {
  const _Scenario(
    this.name, {
    this.signedIn = true,
    this.size = phoneSize,
    this.latency = const Duration(milliseconds: 150),
    this.fail = false,
  });

  final String name;
  final bool signedIn;
  final Size size;
  final Duration latency;

  /// Every request fails, as if offline.
  final bool fail;
}

const _scenarios = [
  _Scenario('signed out on a phone', signedIn: false),
  _Scenario('signed in on a phone'),
  _Scenario('signed in on a desktop', size: desktopSize),
  _Scenario('slow network on a phone', latency: Duration(seconds: 3)),
  _Scenario('offline on a desktop', size: desktopSize, fail: true),
];

// The whole app (MyApp on FakeApiService) under random input. See "Monkey
// testing" in TESTING.md. CI runs it with a fixed seed on every PR, and with
// a random seed and many more steps nightly.
void main() {
  setUpAll(() => Directory(_outDir).createSync(recursive: true));

  for (final scenario in _scenarios) {
    final seed = scenarioSeed(scenario.name);
    final file = scenario.name.replaceAll(' ', '-');
    final replay =
        'flutter test test/monkey/monkey_test.dart '
        '--dart-define=SEED=$monkeySeed --dart-define=MONKEY_STEPS=$monkeySteps '
        '--plain-name "${scenario.name}"';

    testWidgets(scenario.name, timeout: const Timeout(Duration(minutes: 60)), (
      tester,
    ) async {
      final log = File('$_outDir/$file.log')..writeAsStringSync('');
      // Printed first, so a run that hangs until the timeout can still be
      // replayed.
      // ignore: avoid_print
      print('Monkey "${scenario.name}": seed $seed. Replay: $replay');

      SharedPreferences.setMockInitialValues(
        scenario.signedIn
            ? {
                'auth_token': 'tok',
                'auth_user_json': jsonEncode(demoUser.toJson()),
              }
            : {},
      );
      FakeGeolocator.install(addTearDown);
      FakeFilePicker.install(addTearDown);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      tester.setViewport(scenario.size);

      // flutter_map logs every map tile it can't fetch (tests have no
      // network), which buries the monkey's own output. Restored before the
      // test ends, which checks that debugPrint is back to normal.
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message?.startsWith('ClientException: Request to https://tile.') ??
            false) {
          return;
        }
        originalDebugPrint(message, wrapWidth: wrapWidth);
      };

      final boundary = GlobalKey();
      try {
        await withClock(Clock.fixed(_now), () async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MyApp(
                apiService: FakeApiService(
                  latency: scenario.latency,
                  fail: scenario.fail,
                ),
              ),
            ),
          );
          await tester.pump(scenario.latency * 2);

          final monkey = Monkey(
            tester,
            seed: seed,
            steps: monkeySteps,
            replay: replay,
            onLog: (line) =>
                log.writeAsStringSync('$line\n', mode: FileMode.append),
            ignore: _isMapTile,
          );
          try {
            await monkey.run();
          } on MonkeyFailure {
            await _screenshot(tester, boundary, '$_outDir/$file.png');
            rethrow;
          }

          // Let pending requests, timers and animations finish.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 10));
        });
      } finally {
        debugPrint = originalDebugPrint;
      }
    });
  }
}

/// A map tile that didn't load: tests have no network, so every request gets
/// a 400.
bool _isMapTile(FlutterErrorDetails details) =>
    details.library == 'image resource service' &&
    RegExp(
      r'(tile\.openstreetmap\.org|basemaps\.cartocdn\.com)/',
    ).hasMatch('${details.exception}');

/// Saves what was on screen when the monkey failed.
Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey boundary,
  String path,
) async {
  try {
    await tester.pump();
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    });
  } catch (e) {
    // ignore: avoid_print
    print('Could not save a screenshot: $e');
  }
}
