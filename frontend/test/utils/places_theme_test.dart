import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/places_theme.dart';

void main() {
  const light = PlacesTheme.light;
  const dark = PlacesTheme.dark;

  test('maps each status to its color and foreground', () {
    expect(light.statusColor(PlaceStatusKind.open), light.openColor);
    expect(light.statusColor(PlaceStatusKind.closingSoon), light.closingColor);
    expect(light.statusColor(PlaceStatusKind.closed), light.closedColor);
    expect(light.statusColor(PlaceStatusKind.unknown), light.ash);
    expect(light.statusOnContrast(PlaceStatusKind.open), light.openOnContrast);
    expect(
      light.statusOnContrast(PlaceStatusKind.closingSoon),
      light.closingOnContrast,
    );
    expect(
      light.statusOnContrast(PlaceStatusKind.closed),
      light.closedOnContrast,
    );
    expect(light.statusOnContrast(PlaceStatusKind.unknown), light.inkMuted);
  });

  test('copyWith replaces only the given colors', () {
    final copy = light.copyWith(anchor: Colors.pink, markerHome: Colors.cyan);
    expect(copy.anchor, Colors.pink);
    expect(copy.markerHome, Colors.cyan);
    expect(copy.paper, light.paper);
    expect(copy.markerPosition, light.markerPosition);
    final same = light.copyWith();
    expect(same.ink, light.ink);
    expect(same.closedOnContrast, light.closedOnContrast);
  });

  test('lerp blends every color and ignores other extensions', () {
    final start = light.lerp(dark, 0);
    final end = light.lerp(dark, 1);
    expect(start.anchor, light.anchor);
    expect(end.anchor, dark.anchor);
    expect(end.markerWork, dark.markerWork);
    expect(end.closingOnContrast, dark.closingOnContrast);
    final mid = light.lerp(dark, 0.5);
    expect(mid.paper, Color.lerp(light.paper, dark.paper, 0.5));
    expect(light.lerp(null, 0.5), same(light));
  });

  testWidgets('context.places uses the theme extension or brightness', (
    tester,
  ) async {
    late PlacesTheme fromExtension, fromLight, fromDark;
    Widget probe(ThemeData theme, void Function(PlacesTheme) found) => Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          found(context.places);
          return const SizedBox();
        },
      ),
    );
    final custom = light.copyWith(anchor: Colors.pink);
    await tester.pumpWidget(
      Column(
        children: [
          probe(ThemeData(extensions: [custom]), (t) => fromExtension = t),
          probe(ThemeData(brightness: Brightness.light), (t) => fromLight = t),
          probe(ThemeData(brightness: Brightness.dark), (t) => fromDark = t),
        ],
      ),
    );
    expect(fromExtension.anchor, Colors.pink);
    expect(fromLight, same(light));
    expect(fromDark, same(dark));
  });

  test('type scale steps down from display to label', () {
    final sizes = [
      PlacesType.display(Colors.black),
      PlacesType.headline(Colors.black),
      PlacesType.title(Colors.black),
      PlacesType.body(Colors.black),
      PlacesType.bodySmall(Colors.black),
      PlacesType.label(Colors.black),
    ].map((s) => s.fontSize!).toList();
    expect(sizes, [32, 22, 17, 16, 14, 12]);
    expect(PlacesType.body(Colors.red).color, Colors.red);
    expect(PlacesType.display(Colors.black).fontFamilyFallback, isNotEmpty);
  });
}
