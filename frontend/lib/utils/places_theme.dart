import 'package:flutter/material.dart';

// Design tokens for the places surface, scoped via ThemeExtension so the
// rest of the app's existing AppTheme stays untouched. Hex values are sRGB
// approximations of the OKLCH targets documented in DESIGN.md; rework them
// in-device against the Sunlight Rule (DESIGN.md §2) before promoting these
// tokens app-wide.

const _serifFallbacks = <String>[
  'New York',
  'Charter',
  'Iowan Old Style',
  'Georgia',
  'serif',
];

enum PlaceStatusKind { open, closingSoon, closed, unknown }

@immutable
class PlacesTheme extends ThemeExtension<PlacesTheme> {
  const PlacesTheme({
    required this.anchor,
    required this.anchorOnContrast,
    required this.paper,
    required this.paperRaised,
    required this.ash,
    required this.ashSoft,
    required this.ink,
    required this.inkMuted,
    required this.openColor,
    required this.openOnContrast,
    required this.closingColor,
    required this.closingOnContrast,
    required this.closedColor,
    required this.closedOnContrast,
    required this.unknownOutline,
    required this.markerHome,
    required this.markerWork,
    required this.markerPosition,
  });

  final Color
  anchor; // primary warm earth (terracotta family). DESIGN.md §2 Primary.
  final Color
  anchorOnContrast; // foreground laid on anchor (paper-warm on light, ink-warm on dark).
  final Color paper; // default surface (paper-warm light / ink-warm dark).
  final Color paperRaised; // raised surface for sheets, dialogs.
  final Color ash; // dividers, low-contrast borders.
  final Color ashSoft; // softest line, e.g. row separators.
  final Color ink; // primary content text.
  final Color inkMuted; // supporting text, addresses, distance.
  final Color openColor; // semantic — Open Now.
  final Color openOnContrast;
  final Color closingColor; // semantic — Closes Soon.
  final Color closingOnContrast;
  final Color closedColor; // semantic — Closed.
  final Color closedOnContrast;
  final Color unknownOutline; // outlined pill stroke for Hours Unknown.
  final Color markerHome; // centralized marker color for Home.
  final Color markerWork; // centralized marker color for Work.
  final Color markerPosition; // centralized marker color for Current Position.

  Color statusColor(PlaceStatusKind k) => switch (k) {
    PlaceStatusKind.open => openColor,
    PlaceStatusKind.closingSoon => closingColor,
    PlaceStatusKind.closed => closedColor,
    PlaceStatusKind.unknown => ash,
  };

  Color statusOnContrast(PlaceStatusKind k) => switch (k) {
    PlaceStatusKind.open => openOnContrast,
    PlaceStatusKind.closingSoon => closingOnContrast,
    PlaceStatusKind.closed => closedOnContrast,
    PlaceStatusKind.unknown => inkMuted,
  };

  @override
  PlacesTheme copyWith({
    Color? anchor,
    Color? anchorOnContrast,
    Color? paper,
    Color? paperRaised,
    Color? ash,
    Color? ashSoft,
    Color? ink,
    Color? inkMuted,
    Color? openColor,
    Color? openOnContrast,
    Color? closingColor,
    Color? closingOnContrast,
    Color? closedColor,
    Color? closedOnContrast,
    Color? unknownOutline,
    Color? markerHome,
    Color? markerWork,
    Color? markerPosition,
  }) {
    return PlacesTheme(
      anchor: anchor ?? this.anchor,
      anchorOnContrast: anchorOnContrast ?? this.anchorOnContrast,
      paper: paper ?? this.paper,
      paperRaised: paperRaised ?? this.paperRaised,
      ash: ash ?? this.ash,
      ashSoft: ashSoft ?? this.ashSoft,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      openColor: openColor ?? this.openColor,
      openOnContrast: openOnContrast ?? this.openOnContrast,
      closingColor: closingColor ?? this.closingColor,
      closingOnContrast: closingOnContrast ?? this.closingOnContrast,
      closedColor: closedColor ?? this.closedColor,
      closedOnContrast: closedOnContrast ?? this.closedOnContrast,
      unknownOutline: unknownOutline ?? this.unknownOutline,
      markerHome: markerHome ?? this.markerHome,
      markerWork: markerWork ?? this.markerWork,
      markerPosition: markerPosition ?? this.markerPosition,
    );
  }

  @override
  PlacesTheme lerp(ThemeExtension<PlacesTheme>? other, double t) {
    if (other is! PlacesTheme) return this;
    return PlacesTheme(
      anchor: Color.lerp(anchor, other.anchor, t)!,
      anchorOnContrast: Color.lerp(
        anchorOnContrast,
        other.anchorOnContrast,
        t,
      )!,
      paper: Color.lerp(paper, other.paper, t)!,
      paperRaised: Color.lerp(paperRaised, other.paperRaised, t)!,
      ash: Color.lerp(ash, other.ash, t)!,
      ashSoft: Color.lerp(ashSoft, other.ashSoft, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      openColor: Color.lerp(openColor, other.openColor, t)!,
      openOnContrast: Color.lerp(openOnContrast, other.openOnContrast, t)!,
      closingColor: Color.lerp(closingColor, other.closingColor, t)!,
      closingOnContrast: Color.lerp(
        closingOnContrast,
        other.closingOnContrast,
        t,
      )!,
      closedColor: Color.lerp(closedColor, other.closedColor, t)!,
      closedOnContrast: Color.lerp(
        closedOnContrast,
        other.closedOnContrast,
        t,
      )!,
      unknownOutline: Color.lerp(unknownOutline, other.unknownOutline, t)!,
      markerHome: Color.lerp(markerHome, other.markerHome, t)!,
      markerWork: Color.lerp(markerWork, other.markerWork, t)!,
      markerPosition: Color.lerp(markerPosition, other.markerPosition, t)!,
    );
  }

  // Translated from DESIGN.md OKLCH targets. The light theme is the design's home
  // (sunlight scene sentence, §3 of the brief); dark is a system-respecting variant.
  static const light = PlacesTheme(
    anchor: Color(0xFFB14E27), // ≈ oklch(54% 0.14 45)
    anchorOnContrast: Color(0xFFF7F3EC),
    paper: Color(0xFFF7F3EC), // ≈ oklch(96% 0.008 70)
    paperRaised: Color(0xFFFFFAF1), // ≈ oklch(98% 0.008 70)
    ash: Color(0xFFC9C1B2), // ≈ oklch(80% 0.012 70)
    ashSoft: Color(0xFFE5DECF), // ≈ oklch(90% 0.010 70)
    ink: Color(0xFF231F1B), // ≈ oklch(20% 0.010 60)
    inkMuted: Color(0xFF6B6258), // ≈ oklch(46% 0.012 60)
    openColor: Color(0xFF2F6B3A), // ≈ oklch(46% 0.13 145)
    openOnContrast: Color(0xFFF7F3EC),
    closingColor: Color(0xFF9C5E12), // ≈ oklch(50% 0.13 65)
    closingOnContrast: Color(0xFFF7F3EC),
    closedColor: Color(
      0xFF6E665B,
    ), // ≈ oklch(46% 0.02 60), desaturated by design
    closedOnContrast: Color(0xFFF7F3EC),
    unknownOutline: Color(0xFFB0A899),
    markerHome: Color(0xFF3F617A), // Muted Slate Blue
    markerWork: Color(0xFF9E632A), // Muted Bronze Amber
    markerPosition: Color(0xFFB14E27), // Terracotta Anchor
  );

  static const dark = PlacesTheme(
    anchor: Color(0xFFD97A52), // brightened to hold contrast on dark surface
    anchorOnContrast: Color(0xFF1C1916),
    paper: Color(0xFF1C1916), // warm near-black, never pure #000
    paperRaised: Color(0xFF26221E),
    ash: Color(0xFF3A352E),
    ashSoft: Color(0xFF2D2924),
    ink: Color(0xFFEDE6D9), // warm cream, never pure #fff
    inkMuted: Color(0xFFAFA697),
    openColor: Color(0xFF7CB68A),
    openOnContrast: Color(0xFF1C1916),
    closingColor: Color(0xFFE0A668),
    closingOnContrast: Color(0xFF1C1916),
    closedColor: Color(0xFF8A8278),
    closedOnContrast: Color(0xFF1C1916),
    unknownOutline: Color(0xFF6B6258),
    markerHome: Color(0xFF5B85A6), // Brightened Slate Blue
    markerWork: Color(0xFFC4864B), // Brightened Bronze Amber
    markerPosition: Color(0xFFD97A52), // Brightened Terracotta
  );
}

class PlacesType {
  // Serif display + warm humanist sans body (DESIGN.md §3).
  // Body intentionally uses platform default (SF Pro / Roboto) — system sans is
  // legitimate for product UI (product.md). Serif comes via platform fallback
  // chain until a bundled serif is added.

  static TextStyle display(Color color) => TextStyle(
    fontFamilyFallback: _serifFallbacks,
    color: color,
    fontSize: 32,
    height: 1.05,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
  );

  static TextStyle headline(Color color) => TextStyle(
    fontFamilyFallback: _serifFallbacks,
    color: color,
    fontSize: 22,
    height: 1.15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
  );

  static TextStyle title(Color color) => TextStyle(
    color: color,
    fontSize: 17,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );

  static TextStyle body(Color color) => TextStyle(
    color: color,
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static TextStyle bodySmall(Color color) => TextStyle(
    color: color,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  static TextStyle label(Color color) => TextStyle(
    color: color,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );
}

class PlacesSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

class PlacesRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

class PlacesMotion {
  // DESIGN.md §1: responsive, not choreographed. ease-out-quart curve, modest durations.
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Curve curve = Curves.easeOutQuart;
}

extension PlacesThemeContext on BuildContext {
  PlacesTheme get places =>
      Theme.of(this).extension<PlacesTheme>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? PlacesTheme.dark
          : PlacesTheme.light);
}
