import 'package:flutter/material.dart';

import 'design_tokens.dart';

@immutable
class ArenaTheme extends ThemeExtension<ArenaTheme> {
  const ArenaTheme({required this.tokens});

  final ArenaDesignTokens tokens;

  @override
  ThemeExtension<ArenaTheme> copyWith({ArenaDesignTokens? tokens}) {
    return ArenaTheme(tokens: tokens ?? this.tokens);
  }

  @override
  ThemeExtension<ArenaTheme> lerp(
    covariant ThemeExtension<ArenaTheme>? other,
    double t,
  ) {
    if (other is! ArenaTheme) {
      return this;
    }

    Color blend(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    double mix(double a, double b) => a + (b - a) * t;

    return ArenaTheme(
      tokens: ArenaDesignTokens(
        background: blend(tokens.background, other.tokens.background),
        surface: blend(tokens.surface, other.tokens.surface),
        surfaceMuted: blend(tokens.surfaceMuted, other.tokens.surfaceMuted),
        surfaceContainer:
            blend(tokens.surfaceContainer, other.tokens.surfaceContainer),
        outline: blend(tokens.outline, other.tokens.outline),
        outlineMuted: blend(tokens.outlineMuted, other.tokens.outlineMuted),
        textPrimary: blend(tokens.textPrimary, other.tokens.textPrimary),
        textSecondary: blend(tokens.textSecondary, other.tokens.textSecondary),
        primary: blend(tokens.primary, other.tokens.primary),
        primaryStrong: blend(tokens.primaryStrong, other.tokens.primaryStrong),
        primarySoft: blend(tokens.primarySoft, other.tokens.primarySoft),
        secondary: blend(tokens.secondary, other.tokens.secondary),
        secondaryStrong:
            blend(tokens.secondaryStrong, other.tokens.secondaryStrong),
        onSecondary: blend(tokens.onSecondary, other.tokens.onSecondary),
        tertiary: blend(tokens.tertiary, other.tokens.tertiary),
        success: blend(tokens.success, other.tokens.success),
        error: blend(tokens.error, other.tokens.error),
        shadow: blend(tokens.shadow, other.tokens.shadow),
        warningSurface: blend(tokens.warningSurface, other.tokens.warningSurface),
        successSurface: blend(tokens.successSurface, other.tokens.successSurface),
        dangerSurface: blend(tokens.dangerSurface, other.tokens.dangerSurface),
        rankGold: blend(tokens.rankGold, other.tokens.rankGold),
        rankSilver: blend(tokens.rankSilver, other.tokens.rankSilver),
        rankBronze: blend(tokens.rankBronze, other.tokens.rankBronze),
        primaryGradientStart: blend(
            tokens.primaryGradientStart, other.tokens.primaryGradientStart),
        primaryGradientEnd: blend(
            tokens.primaryGradientEnd, other.tokens.primaryGradientEnd),
        surfaceElevatedSheet: blend(
            tokens.surfaceElevatedSheet, other.tokens.surfaceElevatedSheet),
        highlightStrip:
            blend(tokens.highlightStrip, other.tokens.highlightStrip),
        onHighlightStrip:
            blend(tokens.onHighlightStrip, other.tokens.onHighlightStrip),
        podiumGoldStart:
            blend(tokens.podiumGoldStart, other.tokens.podiumGoldStart),
        podiumGoldEnd: blend(tokens.podiumGoldEnd, other.tokens.podiumGoldEnd),
        podiumSilverStart:
            blend(tokens.podiumSilverStart, other.tokens.podiumSilverStart),
        podiumSilverEnd:
            blend(tokens.podiumSilverEnd, other.tokens.podiumSilverEnd),
        podiumBronzeStart:
            blend(tokens.podiumBronzeStart, other.tokens.podiumBronzeStart),
        podiumBronzeEnd:
            blend(tokens.podiumBronzeEnd, other.tokens.podiumBronzeEnd),
        cardPeach: blend(tokens.cardPeach, other.tokens.cardPeach),
        cardLavender: blend(tokens.cardLavender, other.tokens.cardLavender),
        cardMint: blend(tokens.cardMint, other.tokens.cardMint),
        cardGold: blend(tokens.cardGold, other.tokens.cardGold),
        borderWidth: mix(tokens.borderWidth, other.tokens.borderWidth),
        shadowOffset: mix(tokens.shadowOffset, other.tokens.shadowOffset),
        radiusLarge: mix(tokens.radiusLarge, other.tokens.radiusLarge),
        radiusMedium: mix(tokens.radiusMedium, other.tokens.radiusMedium),
        radiusSmall: mix(tokens.radiusSmall, other.tokens.radiusSmall),
        pageMargin: mix(tokens.pageMargin, other.tokens.pageMargin),
      ),
    );
  }
}

extension ArenaThemeBuildContext on BuildContext {
  ArenaDesignTokens get arenaTokens =>
      Theme.of(this).extension<ArenaTheme>()!.tokens;
}