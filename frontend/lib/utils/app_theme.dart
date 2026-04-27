import 'package:flutter/material.dart';

class AppColors {
  // Primary functionality
  static const Color primary = Colors.blue;
  static const Color primaryContainer = Color(0xFFE3F2FD); // Light blue

  // Secondary functionality
  static const Color secondary = Colors.teal;

  // Neutral colors
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color grey = Colors.grey;
  static const Color lightGrey = Color(0xFFEEEEEE);
  static const Color darkGrey = Color(0xFF424242);

  // Semantic colors
  static const Color error = Colors.red;
  static const Color success = Colors.green;
}

class AppTextStyles {
  // We remove hardcoded colors to allow Theme to handle them
  static const TextStyle heading1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(fontSize: 16, height: 1.5);

  static const TextStyle bodySmall = TextStyle(fontSize: 14, height: 1.4);

  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );
}

class AppTheme {
  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme colors) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 2,
        ),
      );

  static InputDecorationTheme _inputDecorationTheme(ColorScheme colors) =>
      InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      );

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.white,
      onSurface: AppColors.black,
      onSurfaceVariant: AppColors.darkGrey,
    ),
    scaffoldBackgroundColor: AppColors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.black,
      elevation: 0,
      centerTitle: true,
    ),
    textTheme: const TextTheme(
      displayLarge: AppTextStyles.heading1,
      displayMedium: AppTextStyles.heading2,
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.bodySmall,
      labelLarge: AppTextStyles.label,
    ),
    elevatedButtonTheme: _elevatedButtonTheme(
      ColorScheme.fromSeed(seedColor: AppColors.primary),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    inputDecorationTheme: _inputDecorationTheme(
      ColorScheme.fromSeed(seedColor: AppColors.primary),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.grey,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppColors.white,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      onSurface: Colors.white,
      onSurfaceVariant: Colors.white70,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF121212),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    textTheme: TextTheme(
      displayLarge: AppTextStyles.heading1.copyWith(color: Colors.white),
      displayMedium: AppTextStyles.heading2.copyWith(color: Colors.white),
      bodyLarge: AppTextStyles.body.copyWith(color: Colors.white),
      bodyMedium: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
      labelLarge: AppTextStyles.label.copyWith(color: Colors.white70),
    ),
    elevatedButtonTheme: _elevatedButtonTheme(
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    inputDecorationTheme: _inputDecorationTheme(
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Colors.white38,
      type: BottomNavigationBarType.fixed,
      backgroundColor: Color(0xFF1E1E1E),
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E1E),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
    ),
  );
}
