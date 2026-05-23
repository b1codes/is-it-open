import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Technical Luxury Design System Tokens
class AppColors {
  // Brand Anchor
  static const Color terracotta = Color(0xFFD66A4D); // oklch(60% 0.12 45)

  // Neutrals (Paper & Ink)
  static const Color paperWarm = Color(0xFFF9F7F2); // oklch(97% 0.008 60)
  static const Color inkWarm = Color(0xFF363430); // oklch(20% 0.01 60)
  static const Color inkWarmMuted = Color(0xFF736F6B); // oklch(45% 0.02 60)

  // Semantic
  static const Color openGreen = Color(0xFF5FB467); // oklch(60% 0.13 145)
  static const Color closingAmber = Color(0xFFE7A23F); // oklch(72% 0.16 75)
  static const Color closedSlate = Color(0xFF736F6B); // oklch(45% 0.02 60)

  // Interaction (Thermal Glow)
  static const Color thermalCore = Color(0xFFFF3B30);
  static const Color thermalCorona = Color(0xFFFF9500);

  // Glass Material
  static const Color glassSurface = Color(0x0DFFFFFF); // rgba(255, 255, 255, 0.05)
  static const Color glassBorder = Color(0x1AFFFFFF); // semi-transparent white
}

/// Custom Theme Extension for Is It Open specific visual properties
@immutable
class AppEffects extends ThemeExtension<AppEffects> {
  const AppEffects({
    required this.glassBlur,
    required this.glassOpacity,
    required this.thermalGlowGradient,
    required this.dragResistance,
  });

  final double glassBlur;
  final double glassOpacity;
  final Gradient thermalGlowGradient;
  final double dragResistance;

  @override
  AppEffects copyWith({
    double? glassBlur,
    double? glassOpacity,
    Gradient? thermalGlowGradient,
    double? dragResistance,
  }) {
    return AppEffects(
      glassBlur: glassBlur ?? this.glassBlur,
      glassOpacity: glassOpacity ?? this.glassOpacity,
      thermalGlowGradient: thermalGlowGradient ?? this.thermalGlowGradient,
      dragResistance: dragResistance ?? this.dragResistance,
    );
  }

  @override
  AppEffects lerp(ThemeExtension<AppEffects>? other, double t) {
    if (other is! AppEffects) return this;
    return AppEffects(
      glassBlur: lerpDouble(glassBlur, other.glassBlur, t) ?? glassBlur,
      glassOpacity: lerpDouble(glassOpacity, other.glassOpacity, t) ?? glassOpacity,
      thermalGlowGradient: Gradient.lerp(thermalGlowGradient, other.thermalGlowGradient, t)!,
      dragResistance: lerpDouble(dragResistance, other.dragResistance, t) ?? dragResistance,
    );
  }

  static double? lerpDouble(double? a, double? b, double t) {
    if (a == null && b == null) return null;
    a ??= 0.0;
    b ??= 0.0;
    return a + (b - a) * t;
  }
}

class AppTheme {
  static final AppEffects _effects = AppEffects(
    glassBlur: 20.0,
    glassOpacity: 0.05,
    thermalGlowGradient: const LinearGradient(
      colors: [AppColors.thermalCore, AppColors.thermalCorona],
    ),
    dragResistance: 0.15,
  );

  static final TextTheme _textTheme = TextTheme(
    displayLarge: GoogleFonts.montserrat(
      fontSize: 34,
      fontWeight: FontWeight.bold,
      color: AppColors.inkWarm,
    ),
    displayMedium: GoogleFonts.montserrat(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppColors.inkWarm,
    ),
    titleLarge: GoogleFonts.openSans(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: AppColors.inkWarm,
    ),
    bodyLarge: GoogleFonts.openSans(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.inkWarm,
      height: 1.5,
    ),
    bodyMedium: GoogleFonts.openSans(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.inkWarmMuted,
      height: 1.4,
    ),
    labelLarge: GoogleFonts.openSans(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.inkWarm,
      letterSpacing: 0.05, // 5% tracking for small labels
    ),
  );

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.terracotta,
      onPrimary: Colors.white,
      secondary: AppColors.inkWarm,
      onSecondary: AppColors.paperWarm,
      error: AppColors.thermalCore,
      onError: Colors.white,
      surface: AppColors.paperWarm,
      onSurface: AppColors.inkWarm,
      outline: AppColors.inkWarmMuted,
    ),
    scaffoldBackgroundColor: AppColors.paperWarm,
    textTheme: _textTheme,
    extensions: [_effects],
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.montserrat(
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0, // Elevation is earned, not default
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.inkWarmMuted, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.inkWarmMuted, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.terracotta, width: 1.5),
      ),
      contentPadding: const EdgeInsets.all(16),
      labelStyle: GoogleFonts.openSans(color: AppColors.inkWarmMuted),
      hintStyle: GoogleFonts.openSans(color: AppColors.inkWarmMuted.withValues(alpha: 0.5)),
    ),
  );

  // Dark theme follows the same principles but with adjusted elevations
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.terracotta,
      brightness: Brightness.dark,
      primary: AppColors.terracotta,
      surface: const Color(0xFF1A1918), // Slightly lighter than pure black
      onSurface: AppColors.paperWarm,
    ),
    scaffoldBackgroundColor: const Color(0xFF141312),
    textTheme: _textTheme.apply(
      bodyColor: AppColors.paperWarm,
      displayColor: AppColors.paperWarm,
    ),
    extensions: [_effects],
  );
}
