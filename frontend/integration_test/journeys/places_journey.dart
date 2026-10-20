import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/places/saved_place_row.dart';
import 'package:frontend/components/places/saved_place_tile.dart';
import 'package:frontend/components/places/status_pill.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/places/place_detail_screen.dart';
import 'package:frontend/screens/places/plan_visit_screen.dart';

import '../helpers/e2e.dart';

extension on WidgetTester {
  Future<void> search(String query) async {
    await openTab('Search');
    final field = find.widgetWithText(TextField, 'Search for a place...');
    await waitFor(field);
    await typeInto(field, query);
    await tapAndSettle(find.widgetWithText(ElevatedButton, 'Search'));
  }

  Future<void> openResult(String name) async {
    await waitFor(find.text(name));
    await tapAndSettle(find.text(name));
    await waitFor(find.byType(PlaceDetailScreen));
  }

  String statusText() {
    final pill = find.descendant(
      of: find.byType(PlaceDetailScreen),
      matching: find.byType(StatusPill),
    );
    return widget<Text>(
      find.descendant(of: pill.first, matching: find.byType(Text)),
    ).data!;
  }

  Future<void> back() =>
      tapAndSettle(find.byIcon(Icons.arrow_back_rounded).last);

  /// Long-presses a saved place's row (not its card on today's route) to
  /// open its actions.
  Future<void> longPressPlace(String name) async {
    await settle(const Duration(milliseconds: 400));
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byWidgetPredicate(
        (w) => w is SavedPlaceRow || w is SavedPlaceTile,
      ),
    );
    await longPress(row.first);
    await settle();
  }
}

/// Search (TomTom stub plus places only the local database has), place
/// details, and the bookmark lifecycle in My Places.
void placesJourneys() {
  late BackendApi api;
  setUp(() => api = BackendApi());

  Future<E2eUser> signedIn(WidgetTester tester, String prefix) async {
    final user = await api.register(prefix);
    await storeSession(user);
    await tester.launchApp();
    await tester.waitFor(find.byType(HomeScreen));
    return user;
  }

  journey('search finds places and their details show open or closed', (
    tester,
  ) async {
    await signedIn(tester, 'search');

    await tester.search('all day');
    await tester.openResult('All Day Diner');
    expect(tester.statusText(), contains('Open'));
    expect(tester.statusText(), contains('24 hours'));
    expect(find.text('24 Bleecker Street, New York, NY 10014'), findsOneWidget);
    await tester.back();

    await tester.search('night owl');
    await tester.openResult('Night Owl Bakery');
    // Open 03:00-03:01 every day, so closed at any other minute.
    final now = DateTime.now();
    if (!(now.hour == 3 && now.minute == 0)) {
      expect(tester.statusText(), startsWith('Closed'));
    }
    await tester.back();

    // Only in the local database (seed_e2e), merged into TomTom's results.
    await tester.search('garden');
    await tester.waitFor(find.text('Riverside Community Garden'));
  });

  journey('a bookmark appears in My Places and can be pinned, marked, '
      'given a visit length, and removed', (tester) async {
    final user = await signedIn(tester, 'bookmark');

    await tester.search("joe's pizza");
    await tester.openResult("Joe's Pizza");
    await tester.tapAndSettle(find.text("Add to today's route"));
    await tester.waitFor(find.text("On today's route"));
    // Saved now, so the detail offers planning a visit.
    await tester.tapAndSettle(find.text('Plan visit'));
    await tester.waitFor(find.byType(PlanVisitScreen));
    await tester.tapAndSettle(find.text('45 min'));
    await tester.waitFor(find.textContaining("We'll use 45 min"));
    await tester.back();
    await tester.back();

    await tester.openTab('My Places');
    await tester.waitFor(find.text("Joe's Pizza"));
    var saved = (await api.bookmarks(user)).single;
    expect(saved['place']['name'], "Joe's Pizza");
    expect(saved['is_pinned'], isFalse);
    expect(saved['average_visit_length'], 45);

    await tester.longPressPlace("Joe's Pizza");
    await tester.tapAndSettle(find.text('Pin'));
    await tester.longPressPlace("Joe's Pizza");
    await tester.waitFor(find.text('Unpin'));
    await tester.tapAndSettle(find.text('Move to want to visit'));
    saved = (await api.bookmarks(user)).single;
    expect(saved['is_pinned'], isTrue);
    expect(saved['is_check_it_out'], isTrue);

    await tester.longPressPlace("Joe's Pizza");
    await tester.waitFor(find.text('Mark as visited'));
    await tester.tapAndSettle(find.text('Remove'));
    await tester.waitForAbsent(find.text("Joe's Pizza"));
    expect(await api.bookmarks(user), isEmpty);
  });

  journey('a quick-added place is saved and can be relabelled', (tester) async {
    final user = await signedIn(tester, 'quickadd');

    await tester.openTab('My Places');
    await tester.tapAndSettle(find.text('Add a custom place'));
    await tester.enterField('Name', "Dad's house");
    await tester.enterField('Address', '9 Elm Street, Springfield');
    await tester.tapAndSettle(find.text('Save place'));
    await tester.waitFor(find.text("Dad's house"));

    final saved = (await api.bookmarks(user)).single;
    expect(saved['place']['name'], "Dad's house");
    expect(saved['place']['address'], '9 Elm Street, Springfield');
    expect(saved['place']['tomtom_id'], startsWith('custom_'));

    // A custom place's label goes through the bookmark-graphic endpoint.
    await tester.tapAndSettle(find.text("Dad's house").first);
    await tester.waitFor(find.byType(PlaceDetailScreen));
    final label = find.widgetWithText(TextField, 'Label');
    await tester.waitFor(label);
    await tester.typeInto(label, "Dad's place");
    await tester.tapAndSettle(find.text('Save label'));
    await tester.waitFor(find.text("Dad's place"));
    await tester.back();
    await tester.waitFor(find.text("Dad's place"));
    expect((await api.bookmarks(user)).single['custom_name'], "Dad's place");
  });
}
