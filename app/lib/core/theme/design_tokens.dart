import 'package:flutter/material.dart';

@immutable
class ArenaDesignTokens {
  const ArenaDesignTokens({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.outline,
    required this.outlineMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.primaryStrong,
    required this.secondary,
    required this.tertiary,
    required this.success,
    required this.error,
    required this.shadow,
    required this.borderWidth,
    required this.shadowOffset,
    required this.radiusLarge,
    required this.radiusMedium,
    required this.radiusSmall,
    required this.pageMargin,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color outline;
  final Color outlineMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color primaryStrong;
  final Color secondary;
  final Color tertiary;
  final Color success;
  final Color error;
  final Color shadow;
  final double borderWidth;
  final double shadowOffset;
  final double radiusLarge;
  final double radiusMedium;
  final double radiusSmall;
  final double pageMargin;

  static const ArenaDesignTokens light = ArenaDesignTokens(
    background: Color(0xFFF9F9F9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEEEEE),
    outline: Color(0xFF111111),
    outlineMuted: Color(0xFFCFC6AF),
    textPrimary: Color(0xFF1B1B1B),
    textSecondary: Color(0xFF4C4735),
    primary: Color(0xFFFFDE59),
    primaryStrong: Color(0xFF705D00),
    secondary: Color(0xFF73F6FB),
    tertiary: Color(0xFFFFD4E7),
    success: Color(0xFF2EAD4F),
    error: Color(0xFFBA1A1A),
    shadow: Color(0xFF111111),
    borderWidth: 3,
    shadowOffset: 4,
    radiusLarge: 16,
    radiusMedium: 12,
    radiusSmall: 8,
    pageMargin: 20,
  );

  static const ArenaDesignTokens dark = ArenaDesignTokens(
    background: Color(0xFF131313),
    surface: Color(0xFF201F1F),
    surfaceMuted: Color(0xFF2A2A2A),
    outline: Color(0xFF988D9F),
    outlineMuted: Color(0xFF4D4354),
    textPrimary: Color(0xFFE5E2E1),
    textSecondary: Color(0xFFCFC2D6),
    primary: Color(0xFFDDB7FF),
    primaryStrong: Color(0xFF6900B3),
    secondary: Color(0xFF4AE176),
    tertiary: Color(0xFF4CD7F6),
    success: Color(0xFF4AE176),
    error: Color(0xFFFFB4AB),
    shadow: Color(0xFF313030),
    borderWidth: 3,
    shadowOffset: 6,
    radiusLarge: 16,
    radiusMedium: 12,
    radiusSmall: 8,
    pageMargin: 16,
  );
}