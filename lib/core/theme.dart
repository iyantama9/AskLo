import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // AskLo Purple Palette
  static const Color _primaryPurple = Color(0xFF7C3AED);
  static const Color _deepViolet = Color(0xFF5B21B6);
  static const Color _lightPurple = Color(0xFFA78BFA);
  static const Color _palePurple = Color(0xFFEDE9FE);

  // Dark theme surfaces
  static const Color _darkBg = Color(0xFF0F0F14);
  static const Color _darkSurface = Color(0xFF1A1A24);
  static const Color _darkSurfaceVariant = Color(0xFF24243A);

  // Light theme surfaces
  static const Color _lightBg = Color(0xFFFAF9FF);
  static const Color _lightSurface = Color(0xFFFFFFFF);

  static const String _fontFamily = 'Inter';

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _fontFamily,
      colorScheme: ColorScheme.dark(
        primary: _primaryPurple,
        secondary: _lightPurple,
        tertiary: _deepViolet,
        surface: _darkSurface,
        surfaceContainerHighest: _darkSurfaceVariant,
        onPrimary: Colors.white,
        onSurface: Colors.white.withValues(alpha: 0.92),
        onSurfaceVariant: Colors.white.withValues(alpha: 0.6),
        outline: Colors.white.withValues(alpha: 0.12),
      ),
      scaffoldBackgroundColor: _darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBg,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: _primaryPurple, width: 1.5),
        ),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryPurple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: _lightPurple),
      ),
      cardTheme: CardThemeData(
        color: _darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: _fontFamily,
      colorScheme: ColorScheme.light(
        primary: _primaryPurple,
        secondary: _deepViolet,
        tertiary: _lightPurple,
        surface: _lightSurface,
        surfaceContainerHighest: _palePurple,
        onPrimary: Colors.white,
        onSurface: const Color(0xFF1A1A2E),
        onSurfaceVariant: const Color(0xFF64648C),
        outline: const Color(0xFFE2E2F0),
      ),
      scaffoldBackgroundColor: _lightBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightBg,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0EDFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: Color(0xFFE2E2F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: _primaryPurple, width: 1.5),
        ),
        hintStyle: const TextStyle(color: Color(0xFF9898B8)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryPurple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE8E8F4)),
        ),
      ),
    );
  }
}
