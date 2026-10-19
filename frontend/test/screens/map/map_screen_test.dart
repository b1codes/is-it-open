import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_bloc.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:latlong2/latlong.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

List<LatLng> _markerPoints(WidgetTester tester) => [
  for (final layer in tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)))
    for (final m in layer.markers) m.point,
];

LatLng _center(WidgetTester tester) => tester
    .widget<FlutterMap>(find.byType(FlutterMap))
    .mapController!
    .camera
    .center;

void main() {
  final here = fakePosition(40.75, -73.98);
  const herePoint = LatLng(40.75, -73.98);
  final noHome = User.fromJson({
    ...demoUser.toJson(),
    'home_lat': null,
    'home_lng': null,
    'work_lat': null,
    'work_lng': null,
  });

  Future<void> pump(
    WidgetTester tester, {
    FakeGeolocator? geolocator,
    User? user,
    Widget screen = const MapScreen(),
    Size size = desktopSize,
    bool apiFails = false,
  }) async {
    FakeGeolocator.install(addTearDown, geolocator);
    await tester.pumpApp(
      screen,
      authState: AuthAuthenticated(user: user ?? demoUser),
      size: size,
      apiFails: apiFails,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the map immediately', (tester) async {
    FakeGeolocator.install(addTearDown);
    await tester.pumpApp(const MapScreen());
    expect(find.byType(FlutterMap), findsOneWidget);
    await tester.unmount();
  });

  group('position', () {
    testWidgets('shows and centres on the device without a home', (
      tester,
    ) async {
      await pump(
        tester,
        geolocator: FakeGeolocator(position: here),
        user: noHome,
      );
      expect(_markerPoints(tester), contains(herePoint));
      expect(_center(tester), herePoint);
      await tester.unmount();
    });

    testWidgets('stays on home but still shows the device', (tester) async {
      await pump(tester, geolocator: FakeGeolocator(position: here));
      expect(_markerPoints(tester), contains(herePoint));
      expect(_center(tester), LatLng(demoUser.homeLat!, demoUser.homeLng!));
      await tester.unmount();
    });

    testWidgets('follows the device when the user asked to', (tester) async {
      await pump(
        tester,
        geolocator: FakeGeolocator(position: here),
        user: User.fromJson({
          ...demoUser.toJson(),
          'use_current_location': true,
        }),
      );
      expect(_center(tester), herePoint);
      await tester.unmount();
    });

    for (final (why, geolocator) in [
      ('location services are off', FakeGeolocator(serviceEnabled: false)),
      (
        'permission is refused',
        FakeGeolocator(permission: LocationPermission.denied),
      ),
      (
        'permission is denied forever',
        FakeGeolocator(permission: LocationPermission.deniedForever),
      ),
      ('the position fails', FakeGeolocator(positionError: Exception('x'))),
    ]) {
      testWidgets('falls back to home when $why', (tester) async {
        await pump(tester, geolocator: geolocator);
        expect(_markerPoints(tester), isNot(contains(herePoint)));
        expect(_center(tester), LatLng(demoUser.homeLat!, demoUser.homeLng!));
        await tester.unmount();
      });
    }

    testWidgets('falls back to New York without a home', (tester) async {
      await pump(
        tester,
        geolocator: FakeGeolocator(serviceEnabled: false),
        user: noHome,
      );
      expect(_center(tester), const LatLng(40.7128, -74.0060));
      await tester.unmount();
    });
  });
  group('places sidebar', () {
    final coffee = coffeePlace.location;
    final gym = gymPlace.location;

    testWidgets('lists places and shows pinned ones by default', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('My Places'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(5));
      expect(
        _markerPoints(tester),
        containsAll([coffee, bistroPlace.location]),
      );
      expect(_markerPoints(tester), isNot(contains(gym)));
      // Home and work markers.
      expect(
        _markerPoints(tester),
        containsAll([
          LatLng(demoUser.homeLat!, demoUser.homeLng!),
          LatLng(demoUser.workLat!, demoUser.workLng!),
        ]),
      );
      await tester.unmount();
    });

    testWidgets('checking a place adds its marker', (tester) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, gymPlace.name));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), contains(gym));
      await tester.tap(find.widgetWithText(CheckboxListTile, gymPlace.name));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), isNot(contains(gym)));
      await tester.unmount();
    });

    testWidgets('unchecking a pinned place turns off "show pinned"', (
      tester,
    ) async {
      await pump(tester);
      SwitchListTile pinnedSwitch() => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Show Pinned Locations'),
      );
      expect(pinnedSwitch().value, isTrue);
      await tester.tap(find.widgetWithText(CheckboxListTile, coffeePlace.name));
      await tester.pumpAndSettle();
      expect(pinnedSwitch().value, isFalse);
      // Re-checking every pinned place turns it back on.
      await tester.tap(find.widgetWithText(CheckboxListTile, coffeePlace.name));
      await tester.pumpAndSettle();
      expect(pinnedSwitch().value, isTrue);
      await tester.unmount();
    });

    testWidgets('the pinned switch hides and shows pinned markers', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Show Pinned Locations'));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), isNot(contains(coffee)));
      await tester.tap(find.text('Show Pinned Locations'));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), contains(coffee));
      await tester.unmount();
    });

    testWidgets('hide all clears every place marker', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Hide All'));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), isNot(contains(coffee)));
      expect(find.byTooltip('Hide All'), findsNothing);
      await tester.unmount();
    });

    testWidgets('refresh reloads the places', (tester) async {
      await pump(tester);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(5));
      await tester.unmount();
    });

    testWidgets('shows an empty state, also when loading fails', (
      tester,
    ) async {
      await pump(tester, apiFails: true);
      expect(find.text('No saved places yet'), findsOneWidget);
      await tester.unmount();
    });

    testWidgets('collapses to icons that still toggle markers', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Collapse Sidebar'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byTooltip('Hide Pinned'), findsOneWidget);

      await tester.tap(find.byTooltip(gymPlace.name));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), contains(gym));
      await tester.tap(find.byTooltip(coffeePlace.name));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show Pinned'), findsOneWidget);

      await tester.tap(find.byTooltip('Show Pinned'));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), contains(coffee));
      await tester.tap(find.byTooltip('Hide Pinned'));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), isNot(contains(coffee)));

      await tester.tap(find.byTooltip('Hide All Markers'));
      await tester.pumpAndSettle();
      expect(_markerPoints(tester), isNot(contains(gym)));

      await tester.tap(find.byTooltip('Refresh Places'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand Sidebar'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(5));
      await tester.unmount();
    });

    testWidgets('on a phone the sidebar is a drawer', (tester) async {
      await pump(tester, size: phoneSize);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(5));
      await tester.unmount();
    });
  });

  testWidgets('embedded, it is just the map, and markers report taps', (
    tester,
  ) async {
    final tapped = <SavedPlace>[];
    await pump(
      tester,
      screen: Scaffold(
        body: MapScreen(embedded: true, onPlaceTapped: tapped.add),
      ),
    );
    expect(find.byType(AppBar), findsNothing);
    final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final coffeeMarker = layer.markers.firstWhere(
      (m) => m.point == coffeePlace.location,
    );
    await tester.tap(find.byWidget(coffeeMarker.child));
    expect(tapped.single.place.tomtomId, 'tt_coffee');
    await tester.unmount();
  });

  testWidgets('uses dark tiles in dark mode', (tester) async {
    FakeGeolocator.install(addTearDown);
    await tester.pumpApp(
      const MapScreen(),
      themeMode: ThemeMode.dark,
      size: desktopSize,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
      contains('dark_all'),
    );
    expect(
      tester.element(find.byType(MapScreen)).read<AuthBloc>().state,
      isA<AuthAuthenticated>(),
    );
    await tester.unmount();
  });
}
