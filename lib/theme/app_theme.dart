import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralised theme definitions. Premium feel: deep emerald primary, soft
/// off-white surfaces in light mode, near-black surfaces with green accents
/// in dark mode. Both modes share the same Tamil-friendly text theme.
class AppTheme {
  static const _seed = Color(0xFF1B5E20); // Deep emerald

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return _base(colorScheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFFAFBF7),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF121512),
      surfaceContainerHighest: const Color(0xFF1B201B),
    );
    return _base(colorScheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0E110E),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF121512),
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData _base(ColorScheme colorScheme) {
    final baseText = GoogleFonts.notoSansTamilTextTheme(
      ThemeData(brightness: colorScheme.brightness).textTheme,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: baseText,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: colorScheme.surfaceContainerHighest,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
