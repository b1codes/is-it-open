import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/places/address_map_thumb.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('0,0 is treated as "no location"', () {
    expect(AddressMapThumb.hasUsableLocation(const LatLng(0, 0)), isFalse);
    expect(AddressMapThumb.hasUsableLocation(const LatLng(0, 1)), isTrue);
    expect(AddressMapThumb.hasUsableLocation(const LatLng(40.7, -74)), isTrue);
  });

  Future<TileLayer> pump(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const Center(
          child: AddressMapThumb(location: LatLng(40.742, -74.0048), size: 96),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<TileLayer>(find.byType(TileLayer));
  }

  testWidgets('draws a static map with a pin at the location', (tester) async {
    final tiles = await pump(tester, Brightness.light);
    expect(tiles.urlTemplate, contains('openstreetmap'));
    expect(tester.getSize(find.byType(AddressMapThumb)), const Size(96, 96));
    final marker = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(marker.markers.single.point, const LatLng(40.742, -74.0048));
    expect(find.byType(IgnorePointer), findsWidgets);
  });

  testWidgets('uses dark tiles on a dark theme', (tester) async {
    final tiles = await pump(tester, Brightness.dark);
    expect(tiles.urlTemplate, contains('dark_all'));
  });
}
