import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/place.dart';
import 'package:frontend/models/saved_place.dart';
import 'package:frontend/utils/graphics_helper.dart';
import 'package:latlong2/latlong.dart';

SavedPlace _savedPlace({String? color}) => SavedPlace(
  id: 1,
  place: const Place(
    tomtomId: 't1',
    name: 'Cafe',
    address: '1 Main St',
    location: LatLng(0, 0),
  ),
  color: color,
);

void main() {
  group('GraphicsHelper.colorForSavedPlace', () {
    test('uses the stored ARGB hex color as-is', () {
      final hex = Colors.blue.toARGB32().toRadixString(16);
      expect(
        GraphicsHelper.colorForSavedPlace(_savedPlace(color: hex), 0),
        Color(Colors.blue.toARGB32()),
      );
      // Alpha from the stored value is preserved, not forced to opaque.
      expect(
        GraphicsHelper.colorForSavedPlace(_savedPlace(color: '80112233'), 0),
        const Color(0x80112233),
      );
    });

    test('falls back to the palette slot when color is null or empty', () {
      const palette = GraphicsHelper.defaultPalette;
      expect(GraphicsHelper.colorForSavedPlace(_savedPlace(), 2), palette[2]);
      expect(
        GraphicsHelper.colorForSavedPlace(_savedPlace(color: ''), 1),
        palette[1],
      );
    });

    test('falls back to the palette when the color does not parse', () {
      expect(
        GraphicsHelper.colorForSavedPlace(_savedPlace(color: 'not-hex'), 0),
        GraphicsHelper.defaultPalette[0],
      );
    });

    test('wraps the palette index', () {
      const palette = GraphicsHelper.defaultPalette;
      expect(
        GraphicsHelper.colorForSavedPlace(_savedPlace(), palette.length + 3),
        palette[3],
      );
    });
  });
}
