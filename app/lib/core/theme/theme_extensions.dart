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