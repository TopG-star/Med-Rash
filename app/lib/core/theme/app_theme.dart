import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'theme_extensions.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    const ArenaDesignTokens tokens = ArenaDesignTokens.light;

    final TextTheme textTheme = Typography.blackMountainView.copyWith(
      headlineLarge: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.45,
      ),
      bodyMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.45,
      ),
      labelMedium: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ).apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: tokens.background,
      colorScheme: ColorScheme.light(
        primary: tokens.primaryStrong,
        onPrimary: Colors.white,
        secondary: tokens.secondary,
        onSecondary: tokens.textPrimary,
        surface: tokens.surface,
        onSurface: tokens.textPrimary,
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
        titleTextStyle: textTheme.headlineMedium,
      ),
    );
  }
}