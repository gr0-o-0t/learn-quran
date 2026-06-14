import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Color Tokens
  static const Color forestGreen = Color(0xff0f5132);
  static const Color emeraldGreen = Color(0xff198754);
  static const Color softIvory = Color(0xfffdfbf7);
  static const Color surfaceMint = Color(0xfff5f7f4);
  static const Color textCharcoal = Color(0xff2c302e);
  static const Color textMuted = Color(0xff5c6460);
  static const Color accentGold = Color(0xffd4af37);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: forestGreen,
        secondary: emeraldGreen,
        surface: softIvory,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textCharcoal,
        onSurfaceVariant: textMuted,
        tertiary: accentGold,
      ),
      scaffoldBackgroundColor: softIvory,
      cardTheme: const CardThemeData(
        color: surfaceMint,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        margin: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: softIvory,
        foregroundColor: forestGreen,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: TextTheme(
        // Titles and Headers using Outfit
        headlineMedium: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: forestGreen,
          height: 1.3,
        ),
        titleMedium: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textCharcoal,
          height: 1.3,
        ),
        // Translation text and UI text using Inter
        bodyMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: textCharcoal,
          height: 1.65,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textMuted,
          height: 1.4,
        ),
      ),
    );
  }

  // Helper method for Quranic Arabic text style
  static TextStyle get arabicTextStyle {
    return GoogleFonts.amiri(
      fontSize: 28,
      height: 2.0,
      color: textCharcoal,
    );
  }
}
