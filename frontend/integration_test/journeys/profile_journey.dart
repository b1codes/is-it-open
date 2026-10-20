import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:latlong2/latlong.dart';

import '../helpers/e2e.dart';

LatLng _mapCenter(WidgetTester tester) => tester
    .widget<FlutterMap>(
      find.descendant(
        of: find.byType(MapScreen),
        matching: find.byType(FlutterMap),
      ),
    )
    .mapController!
    .camera
    .center;

/// Profile edits go through the backend (which geocodes the address with
/// the TomTom stub) and back to the map.
void profileJourneys() {
  testWidgets('a saved home address is geocoded and the map recentres on it', (
    tester,
  ) async {
    final api = BackendApi();
    final user = await api.register('home');
    await storeSession(user);
    await tester.launchApp();
    await tester.waitFor(find.byType(HomeScreen));
    // No home yet: the map starts in New York.
    expect(_mapCenter(tester).latitude, closeTo(40.71, 0.01));

    await tester.openTab('Me');
    await tester.enterField('First Name', 'Hana');
    await tester.tapAndSettle(find.text('Home Address'));
    await tester.enterField('Street Address', '1 Main Street');
    await tester.enterField('City', 'Springfield');
    await tester.enterField('State', 'IL');
    await tester.enterField('Zip Code', '62701');
    await tester.tapAndSettle(find.text('Save Profile'));
    await tester.waitFor(find.text('Profile saved successfully!'));

    final profile = await api.profile(user);
    expect(profile['first_name'], 'Hana');
    expect(profile['home_city'], 'Springfield');
    expect(profile['home_lat'], stubGeocodeLat);
    expect(profile['home_lng'], stubGeocodeLng);

    await tester.openTab('Map');
    final center = _mapCenter(tester);
    expect(center.latitude, closeTo(stubGeocodeLat, 1e-6));
    expect(center.longitude, closeTo(stubGeocodeLng, 1e-6));

    // The edit survives a relaunch, which loads the profile from the backend.
    await tester.relaunchApp();
    await tester.waitFor(find.byType(HomeScreen));
    await tester.openTab('Me');
    await tester.waitFor(find.text('Hana'));
    expect(
      find.widgetWithText(TextFormField, '1 Main Street'),
      findsOneWidget,
    );
  });
}
