import 'package:flutter/material.dart';

@immutable
class ArenaDesignTokens {
  const ArenaDesignTokens({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceContainer,
    required this.outline,
    required this.outlineMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.secondary,
    required this.secondaryStrong,
    required this.onSecondary,
    required this.tertiary,
    required this.success,
    required this.error,
    required this.shadow,
    required this.warningSurface,
    required this.successSurface,
    required this.dangerSurface,
    required this.rankGold,
    required this.rankSilver,
    required this.rankBronze,
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
  final Color surfaceContainer;
  final Color outline;
  final Color outlineMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color primaryStrong;
  final Color primarySoft;
  final Color secondary;
  final Color secondaryStrong;
  final Color onSecondary;
  final Color tertiary;
  final Color success;
  final Color error;
  final Color shadow;
  final Color warningSurface;
  final Color successSurface;
  final Color dangerSurface;
  final Color rankGold;
  final Color rankSilver;
  final Color rankBronze;
  final double borderWidth;
  final double shadowOffset;
  final double radiusLarge;
  final double radiusMedium;
  final double radiusSmall;
  final double pageMargin;

  static const ArenaDesignTokens light = ArenaDesignTokens(
    background: Color(0xFFF9F9FB),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F3FA),
    surfaceContainer: Color(0xFFECEEF0),
    outline: Color(0xFFE5E0EC),
    outlineMuted: Color(0xFFF1ECF7),
    textPrimary: Color(0xFF1E1A2E),
    textSecondary: Color(0xFF5C5470),
    primary: Color(0xFF5300B7),
    primaryStrong: Color(0xFF3D0085),
    primarySoft: Color(0xFFEBDDFF),
    secondary: Color(0xFFFFC329),
    secondaryStrong: Color(0xFFF59E0B),
    onSecondary: Color(0xFF261A00),
    tertiary: Color(0xFFFFD4E7),
    success: Color(0xFF128A3E),
    error: Color(0xFFDC2626),
    shadow: Color(0xFF6D28D9),
    warningSurface: Color(0xFFFFF7E6),
    successSurface: Color(0xFFE8F5EC),
    dangerSurface: Color(0xFFFDECEC),
    rankGold: Color(0xFFFFC329),
    rankSilver: Color(0xFFC0C0C0),
    rankBronze: Color(0xFFCD7F32),
    borderWidth: 1.5,
    shadowOffset: 0,
    radiusLarge: 24,
    radiusMedium: 16,
    radiusSmall: 12,
    pageMargin: 20,
  );

  static const ArenaDesignTokens dark = ArenaDesignTokens(
    background: Color(0xFF131313),
    surface: Color(0xFF201F1F),
    surfaceMuted: Color(0xFF2A2A2A),
    surfaceContainer: Color(0xFF252329),
    outline: Color(0xFF3A2E4A),
    outlineMuted: Color(0xFF2E2538),
    textPrimary: Color(0xFFE5E2E1),
    textSecondary: Color(0xFFCFC2D6),
    primary: Color(0xFFDDB7FF),
    primaryStrong: Color(0xFFB888FF),
    primarySoft: Color(0xFF3D2B5C),
    secondary: Color(0xFFFFD562),
    secondaryStrong: Color(0xFFFFC329),
    onSecondary: Color(0xFF261A00),
    tertiary: Color(0xFF4CD7F6),
    success: Color(0xFF4AE176),
    error: Color(0xFFFFB4AB),
    shadow: Color(0xFF000000),
    warningSurface: Color(0xFF3A2F0F),
    successSurface: Color(0xFF153D24),
    dangerSurface: Color(0xFF3D1515),
    rankGold: Color(0xFFFFD75E),
    rankSilver: Color(0xFFB7B7B7),
    rankBronze: Color(0xFFC68A4C),
    borderWidth: 1.5,
    shadowOffset: 0,
    radiusLarge: 24,
    radiusMedium: 16,
    radiusSmall: 12,
    pageMargin: 16,
  );
}

/// Spacing scale used across MedRash screens. Use these constants instead of
/// hardcoded `SizedBox(height: 8)` literals so vertical rhythm stays consistent
/// across compact, medium, and expanded breakpoints.
class MedRashSpace {
  const MedRashSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Icon sizing scale. Use these instead of bare numeric `size:` literals on
/// `Icon` widgets so glyph rhythm tracks the design system. Theme-invariant
/// (no light/dark variant needed).
class MedRashIconSize {
  const MedRashIconSize._();

  /// 16 dp — inline glyph beside body text, dense chips.
  static const double sm = 16;

  /// 20 dp — default for buttons, list rows, nav rails.
  static const double md = 20;

  /// 24 dp — primary affordances, app-bar actions.
  static const double lg = 24;

  /// 32 dp — hero / empty-state glyphs, large avatars.
  static const double xl = 32;
}