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
    required this.primaryGradientStart,
    required this.primaryGradientEnd,
    required this.surfaceElevatedSheet,
    required this.highlightStrip,
    required this.onHighlightStrip,
    required this.podiumGoldStart,
    required this.podiumGoldEnd,
    required this.podiumSilverStart,
    required this.podiumSilverEnd,
    required this.podiumBronzeStart,
    required this.podiumBronzeEnd,
    required this.cardPeach,
    required this.cardLavender,
    required this.cardMint,
    required this.cardGold,
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

  // ---------- Gamified rebrand additions (P0) ----------
  // These anchor the violet-forward reference look: header gradient, the
  // rounded sheet that drops under the purple header, the orange "doing
  // better" highlight strip, podium tier gradients, and the four pastel
  // card tones used on Home + Discover surfaces.

  /// Top color of the primary header gradient (lighter indigo-violet).
  final Color primaryGradientStart;

  /// Bottom color of the primary header gradient (deeper violet).
  final Color primaryGradientEnd;

  /// Rounded sheet color that sits below the primary header. In light it is
  /// pure white; in dark it is a slightly lifted neutral so the sheet still
  /// reads as elevated above `background`.
  final Color surfaceElevatedSheet;

  /// Saturated orange tile used for "doing better than X%" call-outs.
  final Color highlightStrip;

  /// Foreground used on `highlightStrip`. Always pairs as AA large-text.
  final Color onHighlightStrip;

  /// Podium gold gradient (top of riser → base).
  final Color podiumGoldStart;
  final Color podiumGoldEnd;

  /// Podium silver gradient.
  final Color podiumSilverStart;
  final Color podiumSilverEnd;

  /// Podium bronze gradient.
  final Color podiumBronzeStart;
  final Color podiumBronzeEnd;

  /// Pastel card fill — peach (recent quiz, soft warnings).
  final Color cardPeach;

  /// Pastel card fill — lavender (featured, premium).
  final Color cardLavender;

  /// Pastel card fill — mint (success state, completed).
  final Color cardMint;

  /// Pastel card fill — gold (achievements, badges).
  final Color cardGold;

  final double borderWidth;
  final double shadowOffset;
  final double radiusLarge;
  final double radiusMedium;
  final double radiusSmall;
  final double pageMargin;

  static const ArenaDesignTokens light = ArenaDesignTokens(
    background: Color(0xFFF9F9FB),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF2EEFF),
    surfaceContainer: Color(0xFFECEEF0),
    outline: Color(0xFFE5E0EC),
    outlineMuted: Color(0xFFF1ECF7),
    textPrimary: Color(0xFF1E1A2E),
    textSecondary: Color(0xFF5C5470),
    primary: Color(0xFF6C5CE7),
    primaryStrong: Color(0xFF4F45B8),
    primarySoft: Color(0xFFE8E5FA),
    secondary: Color(0xFFFFC329),
    secondaryStrong: Color(0xFFF59E0B),
    onSecondary: Color(0xFF261A00),
    tertiary: Color(0xFFFFD4E7),
    success: Color(0xFF128A3E),
    error: Color(0xFFDC2626),
    shadow: Color(0xFF4F45B8),
    warningSurface: Color(0xFFFFF7E6),
    successSurface: Color(0xFFE8F5EC),
    dangerSurface: Color(0xFFFDECEC),
    rankGold: Color(0xFFFFC527),
    rankSilver: Color(0xFFBFBFC8),
    rankBronze: Color(0xFFE08F4C),
    primaryGradientStart: Color(0xFF7B6FE8),
    primaryGradientEnd: Color(0xFF5448C6),
    surfaceElevatedSheet: Color(0xFFFFFFFF),
    highlightStrip: Color(0xFFD86A2A),
    onHighlightStrip: Color(0xFFFFFFFF),
    podiumGoldStart: Color(0xFFFFD562),
    podiumGoldEnd: Color(0xFFE8A300),
    podiumSilverStart: Color(0xFFE6E6EE),
    podiumSilverEnd: Color(0xFFA8A8B4),
    podiumBronzeStart: Color(0xFFF2B07A),
    podiumBronzeEnd: Color(0xFFB86A2E),
    cardPeach: Color(0xFFFCD3CC),
    cardLavender: Color(0xFFC5BFF2),
    cardMint: Color(0xFFC8EBD8),
    cardGold: Color(0xFFFFE9A8),
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
    primaryGradientStart: Color(0xFF5A4FBF),
    primaryGradientEnd: Color(0xFF3A3170),
    surfaceElevatedSheet: Color(0xFF2A2738),
    highlightStrip: Color(0xFFB85A22),
    onHighlightStrip: Color(0xFFFFFFFF),
    podiumGoldStart: Color(0xFFE8B340),
    podiumGoldEnd: Color(0xFF8A6000),
    podiumSilverStart: Color(0xFFB7B7C2),
    podiumSilverEnd: Color(0xFF60606A),
    podiumBronzeStart: Color(0xFFC2814E),
    podiumBronzeEnd: Color(0xFF6A3C18),
    cardPeach: Color(0xFF5C3A33),
    cardLavender: Color(0xFF3A3578),
    cardMint: Color(0xFF2E5340),
    cardGold: Color(0xFF5C4220),
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

/// Gradient builders that read the active `ArenaDesignTokens` so widgets stay
/// theme-aware without inlining color stops. Used by the gamified P1+ atoms
/// (header sheet, podium blocks, gradient cards) — exposed in P0 so the
/// rebrand foundation ships with one canonical builder per surface.
class MedRashGradient {
  const MedRashGradient._();

  /// Primary header gradient — top→bottom violet wash sitting behind the
  /// rounded `surfaceElevatedSheet` on Home / Profile.
  static LinearGradient primaryHeader(ArenaDesignTokens t) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[t.primaryGradientStart, t.primaryGradientEnd],
    );
  }

  /// Podium gold riser — top→bottom.
  static LinearGradient podiumGold(ArenaDesignTokens t) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[t.podiumGoldStart, t.podiumGoldEnd],
    );
  }

  /// Podium silver riser — top→bottom.
  static LinearGradient podiumSilver(ArenaDesignTokens t) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[t.podiumSilverStart, t.podiumSilverEnd],
    );
  }

  /// Podium bronze riser — top→bottom.
  static LinearGradient podiumBronze(ArenaDesignTokens t) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[t.podiumBronzeStart, t.podiumBronzeEnd],
    );
  }
}