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
  group('GraphicsHelper.buildProfileGraphic', () {
    Future<(BoxDecoration, Icon)> render(
      WidgetTester tester,
      SavedPlace place, {
      double size = 40,
    }) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GraphicsHelper.buildProfileGraphic(place, size: size),
          ),
        ),
      );
      final box = tester.widget<Container>(find.byType(Container));
      return (
        box.decoration! as BoxDecoration,
        tester.widget<Icon>(find.byType(Icon)),
      );
    }

    testWidgets('draws the stored icon on an opaque stored color', (
      tester,
    ) async {
      final place = SavedPlace(
        id: 1,
        place: _savedPlace().place,
        icon: 'local_cafe',
        color: '80112233',
      );
      final (decoration, icon) = await render(tester, place, size: 50);
      expect(decoration.color, const Color(0xFF112233));
      expect(decoration.shape, BoxShape.circle);
      expect(icon.icon, Icons.local_cafe);
      expect(icon.size, 30);
      expect(tester.getSize(find.byType(Container)), const Size(50, 50));
    });

    testWidgets('defaults to a blue star', (tester) async {
      final (decoration, icon) = await render(tester, _savedPlace());
      expect(decoration.color, Color(Colors.blue.toARGB32()));
      expect(icon.icon, Icons.star);
    });

    testWidgets('falls back for an unknown icon name', (tester) async {
      final place = SavedPlace(
        id: 1,
        place: _savedPlace().place,
        icon: 'not_an_icon',
      );
      final (_, icon) = await render(tester, place);
      expect(icon.icon, Icons.star);
    });

    testWidgets('falls back to blue for a malformed stored color', (
      tester,
    ) async {
      for (final color in ['', 'not-hex']) {
        final (decoration, _) = await render(tester, _savedPlace(color: color));
        expect(decoration.color, Color(Colors.blue.toARGB32()), reason: color);
      }
    });

    test('every available icon name maps to an icon', () {
      expect(GraphicsHelper.availableIcons, hasLength(11));
      expect(GraphicsHelper.availableIcons['work'], Icons.work);
    });
  });
}
