import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'theme_extensions.dart';

class AppTheme {
  const AppTheme._();

  /// Font family used for display / UI emphasis (headlines, titles, buttons,
  /// score counters, navigation labels). Bundled as static .ttf weights 600,
  /// 700, 800 via `pubspec.yaml`.
  static const String displayFontFamily = 'Poppins';

  /// Font family used for dense readable content (quiz bodies, paragraphs,
  /// analytics tables, form helpers). Bundled as the Inter variable font; the
  /// runtime picks the closest weight to whatever the TextStyle requests.
  static const String bodyFontFamily = 'Inter';

  static ThemeData light() {
    const ArenaDesignTokens tokens = ArenaDesignTokens.light;

    // Poppins (display family) for display/headline/title/button slots.
    // Inter (body family) for body/label slots — quiz questions, paragraphs,
    // analytics tables, form helpers — so dense content stays readable.
    final TextTheme textTheme = Typography.blackMountainView
        .copyWith(
          displayLarge: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            height: 1.05,
          ),
          displayMedium: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.1,
          ),
          displaySmall: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
            height: 1.15,
          ),
          headlineLarge: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          headlineMedium: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          headlineSmall: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
          titleLarge: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          titleMedium: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          titleSmall: const TextStyle(
            fontFamily: displayFontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            height: 1.3,
          ),
          bodyLarge: const TextStyle(
            fontFamily: bodyFontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
          bodyMedium: const TextStyle(
            fontFamily: bodyFontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
          bodySmall: const TextStyle(
            fontFamily: bodyFontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
          labelLarge: const TextStyle(
            fontFamily: bodyFontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
          labelMedium: const TextStyle(
            fontFamily: bodyFontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            height: 1.2,
          ),
          labelSmall: const TextStyle(
            fontFamily: bodyFontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            height: 1.2,
          ),
        )
        .apply(
          bodyColor: tokens.textPrimary,
          displayColor: tokens.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: tokens.background,
      colorScheme: ColorScheme.light(
        primary: tokens.primary,
        onPrimary: Colors.white,
        primaryContainer: tokens.primarySoft,
        onPrimaryContainer: tokens.primaryStrong,
        secondary: tokens.secondary,
        onSecondary: tokens.onSecondary,
        surface: tokens.surface,
        onSurface: tokens.textPrimary,
        surfaceContainerHighest: tokens.surfaceContainer,
        outline: tokens.outline,
        outlineVariant: tokens.outlineMuted,
        error: tokens.error,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      extensions: const <ThemeExtension<dynamic>>[
        ArenaTheme(tokens: tokens),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: textTheme.headlineSmall,
      ),
    );
  }
}