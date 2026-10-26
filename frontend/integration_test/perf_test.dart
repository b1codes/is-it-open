import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e.dart';

// Frame timing of the interactions most prone to jank: panning and zooming
// the map, scrolling the calendar, and typing a search. Each runs inside
// traceAction, whose timeline test_driver/perf_driver.dart summarizes and
// checks against its budgets. It needs profile mode, so it runs as a desktop
// app (`make perf-frames`, or nightly in perf.yml), against the E2E stack.
// See "Performance" in TESTING.md.

/// Where the map opens: the pinned places are spread around it.
const _center = (lat: 40.7306, lng: -74.0021);
const _pinnedPlaces = 40;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Draw frames as a device would, not only when the test pumps.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late E2eUser user;

  setUpAll(() async {
    await initApp();
    final api = BackendApi();
    user = await api.register('perf');
    await api.updateProfile(user, {
      'home_lat': _center.lat,
      'home_lng': _center.lng,
      'calendar_subscription_url': stubCalendarUrl,
    });
    final random = Random(42);
    for (var i = 0; i < _pinnedPlaces; i++) {
      await api.bookmarkNewPlace(user, {
        'tomtom_id': '${user.username}-place-$i',
        'name': 'Perf Cafe $i',
        'address': '$i Perf St, New York, NY',
        'location': {
          'lat': _center.lat + (random.nextDouble() - 0.5) * 0.06,
          'lng': _center.lng + (random.nextDouble() - 0.5) * 0.06,
        },
      }, pinned: true);
    }
  });

  setUp(() async {
    await resetDevice();
    await storeSession(user);
  });

  Future<void> openApp(WidgetTester tester) async {
    await tester.launchApp();
    await tester.waitFor(find.byType(HomeScreen));
  }

  journey('map pan and zoom', (tester) async {
    await openApp(tester);
    await tester.openTab('Map');
    // Every pinned place has a marker (plus one for home).
    await tester.waitFor(find.byIcon(Icons.location_on).at(_pinnedPlaces));
    final map = tester.getCenter(find.byType(FlutterMap));

    await binding.traceAction(() async {
      for (final offset in const [
        Offset(-300, 0),
        Offset(0, -200),
        Offset(300, 0),
        Offset(0, 200),
      ]) {
        await tester.timedDragFrom(
          map,
          offset,
          const Duration(milliseconds: 500),
        );
        await tester.settle(const Duration(milliseconds: 300));
      }
      await tester.pinch(map, from: 40, to: 160);
      await tester.settle(const Duration(milliseconds: 300));
      await tester.pinch(map, from: 160, to: 40);
      await tester.settle(const Duration(milliseconds: 300));
    }, reportKey: 'map_pan_zoom');
  });

  journey('calendar scroll', (tester) async {
    await openApp(tester);
    await tester.openTab('Calendar');
    await tester.waitFor(find.text(stubEventTitle));
    // The time grid. The week pager around it doesn't swipe; its buttons
    // turn the page.
    final hours = tester.getCenter(
      find
          .ancestor(
            of: find.text(stubEventTitle).first,
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    );

    await binding.traceAction(() async {
      for (final offset in const [
        Offset(0, -400),
        Offset(0, 400),
        Offset(0, -400),
        Offset(0, 400),
      ]) {
        await tester.timedDragFrom(
          hours,
          offset,
          const Duration(milliseconds: 400),
        );
        await tester.settle(const Duration(milliseconds: 500));
      }
      for (final page in ['Next', 'Next', 'Previous', 'Previous']) {
        await tester.tap(find.byTooltip(page));
        await tester.settle(const Duration(milliseconds: 600));
      }
    }, reportKey: 'calendar_scroll');
  });

  journey('search typing', (tester) async {
    await openApp(tester);
    await tester.openTab('Search');
    final field = find.widgetWithText(TextField, 'Search for a place...');
    await tester.waitFor(field);
    // Profile builds don't route the keyboard through the test's text input
    // by default, so enterText would type nowhere. Register it before the
    // field takes focus and opens its connection.
    binding.testTextInput.register();
    addTearDown(binding.testTextInput.unregister);
    await tester.tapAndSettle(field);

    await binding.traceAction(() async {
      const query = "joe's pizza";
      for (var i = 1; i <= query.length; i++) {
        await tester.enterText(field, query.substring(0, i));
        // About as fast as a quick typist.
        await tester.settle(const Duration(milliseconds: 120));
      }
      await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
      await tester.waitFor(find.text("Joe's Pizza Corner"));
      await tester.settle();
    }, reportKey: 'search_typing');
  });
}

extension on WidgetTester {
  /// Two fingers moving apart (or together) about [center], from [from] to
  /// [to] pixels each side of it: a pinch zoom.
  Future<void> pinch(
    Offset center, {
    required double from,
    required double to,
  }) async {
    final left = await startGesture(center - Offset(from, 0), pointer: 101);
    final right = await startGesture(center + Offset(from, 0), pointer: 102);
    const steps = 20;
    for (var i = 1; i <= steps; i++) {
      final distance = from + (to - from) * i / steps;
      await left.moveTo(center - Offset(distance, 0));
      await right.moveTo(center + Offset(distance, 0));
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await pump();
    }
    await left.up();
    await right.up();
  }
}
