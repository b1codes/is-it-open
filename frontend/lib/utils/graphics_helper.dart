import 'package:flutter/material.dart';
import '../../models/saved_place.dart';

class GraphicsHelper {
  /// Fallback colors for saved places that have no (valid) stored color.
  static const List<Color> defaultPalette = [
    Color(0xFFB14E27), // Anchor
    Color(0xFFD99B52), // Ochre
    Color(0xFF8F7A6A), // Taupe
    Color(0xFF6B5344), // Chestnut
    Color(0xFFB57D65), // Dusty Rose
    Color(0xFF9E8B7E), // Mushroom
  ];

  /// The display color for [savedPlace] on the calendar and map.
  ///
  /// Uses the stored ARGB hex string (e.g. `ff2196f3`) as-is, alpha included;
  /// if it is missing, empty or unparseable, falls back to the
  /// [defaultPalette] slot for [index].
  static Color colorForSavedPlace(SavedPlace savedPlace, int index) {
    final hex = savedPlace.color;
    if (hex != null && hex.isNotEmpty) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(value);
    }
    return defaultPalette[index % defaultPalette.length];
  }

  static final Map<String, IconData> availableIcons = {
    'restaurant': Icons.restaurant,
    'local_cafe': Icons.local_cafe,
    'local_bar': Icons.local_bar,
    'store': Icons.store,
    'shopping_cart': Icons.shopping_cart,
    'fitness_center': Icons.fitness_center,
    'local_hospital': Icons.local_hospital,
    'park': Icons.park,
    'star': Icons.star,
    'home': Icons.home,
    'work': Icons.work,
  };

  static Widget buildProfileGraphic(SavedPlace savedPlace, {double size = 40}) {
    final currentColorHex =
        savedPlace.color ?? Colors.blue.toARGB32().toRadixString(16);
    final currentColor = Color(
      int.parse(currentColorHex, radix: 16),
    ).withValues(alpha: 1.0);
    final currentIconName = savedPlace.icon ?? 'star';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: currentColor, shape: BoxShape.circle),
      child: Icon(
        availableIcons[currentIconName] ?? Icons.star,
        color: Colors.white,
        size: size * 0.6,
      ),
    );
  }
}
