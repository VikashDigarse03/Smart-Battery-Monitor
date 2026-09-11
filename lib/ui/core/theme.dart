import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Application theme for the Battery Monitor app.
///
/// Uses a dark industrial color palette with teal/cyan accents that
/// evoke a professional monitoring/instrumentation feel.
class AppTheme {
  AppTheme._();

  // ─── Brand Colors ────────────────────────────────────────────
  static const Color primary = Color(0xFF00BCD4); // Teal/Cyan
  static const Color primaryDark = Color(0xFF0097A7);
  static const Color primaryLight = Color(0xFF4DD0E1);

  static const Color secondary = Color(0xFF26A69A); // Teal green
  static const Color accent = Color(0xFF00E5FF); // Bright cyan

  // ─── Background Colors ───────────────────────────────────────
  static const Color scaffoldBg = Color(0xFF0D1117); // Very dark blue-black
  static const Color surfaceBg = Color(0xFF161B22); // Card background
  static const Color cardBg = Color(0xFF1C2333); // Elevated card
  static const Color cardBgLight = Color(0xFF232D3F); // Lighter card
  static const Color dialogBg = Color(0xFF1E2736);

  // ─── Status Colors ───────────────────────────────────────────
  static const Color statusGood = Color(0xFF4CAF50); // Green
  static const Color statusWarning = Color(0xFFFF9800); // Amber/Orange
  static const Color statusCritical = Color(0xFFF44336); // Red
  static const Color statusInfo = Color(0xFF2196F3); // Blue
  static const Color statusInactive = Color(0xFF78909C); // Blue-grey

  // ─── Measurement Display Colors ──────────────────────────────
  static const Color voltageColor = Color(0xFF4CAF50); // Green
  static const Color currentColor = Color(0xFF00BCD4); // Cyan
  static const Color temperatureColor = Color(0xFFFF7043); // Deep orange
  static const Color powerColor = Color(0xFFFFD740); // Amber
  static const Color healthColor = Color(0xFF66BB6A); // Light green
  static const Color socColor = Color(0xFF42A5F5); // Light blue

  // ─── Text Colors ─────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF484F58);

  // ─── Dividers & Borders ──────────────────────────────────────
  static const Color divider = Color(0xFF30363D);
  static const Color border = Color(0xFF30363D);
  static const Color borderFocused = primary;

  /// Returns the color for a voltage value based on thresholds.
  static Color getVoltageColor(
    double voltage, {
    double criticalLow = 10.5,
    double warningLow = 11.5,
    double normalLow = 12.0,
    double full = 12.7,
    double overcharge = 14.8,
  }) {
    if (voltage > overcharge) return statusCritical;
    if (voltage >= full) return statusGood;
    if (voltage >= normalLow) return const Color(0xFFCDDC39); // Lime
    if (voltage >= warningLow) return statusWarning;
    return statusCritical;
  }

  /// Returns the color for a temperature value.
  static Color getTemperatureColor(
    double temp, {
    double warning = 45.0,
    double critical = 55.0,
  }) {
    if (temp >= critical) return statusCritical;
    if (temp >= warning) return statusWarning;
    return statusGood;
  }

  /// Returns the color for battery health percentage.
  static Color getHealthColor(int health) {
    if (health >= 80) return statusGood;
    if (health >= 50) return statusWarning;
    return statusCritical;
  }

  /// Returns the color for battery SOC percentage.
  static Color getSocColor(int percent) {
    if (percent > 50) return statusGood;
    if (percent > 25) return statusWarning;
    if (percent > 10) return const Color(0xFFFF5722); // Deep orange
    return statusCritical;
  }

  /// The main application theme.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surfaceBg,
        error: statusCritical,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textPrimary,
        onError: Colors.white,
        outline: border,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          headlineLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
          bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
          bodySmall: TextStyle(fontSize: 12, color: textMuted),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          labelMedium: TextStyle(fontSize: 12, color: textSecondary),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceBg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: statusCritical),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textMuted),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.black,
        elevation: 4,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceBg,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardBg,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardBg,
        selectedColor: primary.withValues(alpha: 0.2),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 13),
      ),
    );
  }
}
