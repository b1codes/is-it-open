import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/shared/side_menu.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import 'package:frontend/screens/search/search_screen.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

double _sheetSize(WidgetTester tester) => tester
    .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
    .controller!
    .size;

void main() {
  group('phone', () {
    testWidgets('starts on the map with a peek bar', (tester) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen());
      await tester.pumpAndSettle();
      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.text('Search or plan route...'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(SideMenu), findsNothing);
      expect(_sheetSize(tester), closeTo(0.08, 0.001));
      await tester.unmount();
    });

    testWidgets('each tab opens its screen in the sheet', (tester) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen());
      await tester.pumpAndSettle();
      for (final (label, screen) in [
        ('My Places', MyPlacesScreen),
        ('Calendar', CalendarScreen),
        ('Search', SearchScreen),
        ('Me', MeScreen),
      ]) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget, reason: label);
        expect(_sheetSize(tester), closeTo(0.5, 0.01), reason: label);
        expect(tester.takeException(), isNull, reason: label);
      }
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(_sheetSize(tester), closeTo(0.08, 0.01));
      await tester.unmount();
    });

    testWidgets('tapping the peek bar opens search', (tester) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search or plan route...'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      await tester.unmount();
    });

    testWidgets('the sheet can be dragged up from the map', (tester) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen());
      await tester.pumpAndSettle();
      await tester.drag(
        find.text('Search or plan route...'),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(_sheetSize(tester), greaterThan(0.3));
      await tester.unmount();
    });

    testWidgets('dragging the sheet down returns to the map tab', (
      tester,
    ) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Me'));
      await tester.pumpAndSettle();
      expect(find.byType(MeScreen), findsOneWidget);
      await tester.fling(find.byType(MeScreen), const Offset(0, 600), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Search or plan route...'), findsOneWidget);
      await tester.unmount();
    });

    testWidgets('tabs open the sheet even when content loads instantly', (
      tester,
    ) async {
      // FakeApiService answers on the next frame here (latency zero), so
      // the list replaces its skeleton mid-animation.
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Places'));
      await tester.pumpAndSettle();
      expect(_sheetSize(tester), closeTo(0.5, 0.01));
      await tester.unmount();
    });
  });

  group('phone sheet with a search that has no list', () {
    Future<void> searchFor(WidgetTester tester, String query) async {
      await tester.tap(find.text('Search').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(TextField),
        ),
        query,
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
    }

    // Each keeps the sheet attached: a tab change still moves it, and it can
    // still be dragged.
    Future<void> expectSheetStillMoves(WidgetTester tester) async {
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(_sheetSize(tester), closeTo(0.08, 0.01));
      await tester.drag(
        find.text('Search or plan route...'),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(_sheetSize(tester), greaterThan(0.3));
    }

    testWidgets('nothing found', (tester) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen());
      await tester.pumpAndSettle();
      await searchFor(tester, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No results found'), findsOneWidget);
      await tester.drag(find.text('No results found'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(_sheetSize(tester), greaterThan(0.5));
      await expectSheetStillMoves(tester);
      await tester.unmount();
    });

    testWidgets('a failed search', (tester) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen(), apiFails: true);
      await tester.pumpAndSettle();
      await searchFor(tester, 'pizza');
      await tester.pumpAndSettle();
      expect(find.textContaining('Error:'), findsOneWidget);
      await expectSheetStillMoves(tester);
      await tester.unmount();
    });

    testWidgets('a search still loading', (tester) async {
      FakeGeolocator.install(addTearDown);
      // Requests never resolve, so the spinner stays (and never settles).
      await tester.pumpApp(const HomeScreen(), apiLatency: null);
      await tester.pump();
      await searchFor(tester, 'pizza');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Map'));
      await tester.pump(); // the sheet animation's first frame
      await tester.pump(const Duration(seconds: 1));
      expect(_sheetSize(tester), closeTo(0.08, 0.01));
      await tester.unmount();
    });
  });

  group('desktop', () {
    testWidgets('uses the side menu and a side panel', (tester) async {
      FakeGeolocator.install(addTearDown);
      await tester.pumpApp(const HomeScreen(), size: desktopSize);
      await tester.pumpAndSettle();
      expect(find.byType(SideMenu), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(DraggableScrollableSheet), findsNothing);

      for (final (label, screen) in [
        ('My Places', MyPlacesScreen),
        ('Calendar', CalendarScreen),
        ('Search', SearchScreen),
        ('Me', MeScreen),
      ]) {
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget, reason: label);
        expect(tester.takeException(), isNull, reason: label);
      }
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(find.byType(MyPlacesScreen), findsNothing);
      await tester.unmount();
    });
  });
}
