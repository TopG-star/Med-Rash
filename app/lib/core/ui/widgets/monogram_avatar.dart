import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// Circular avatar that renders 1–2 initials derived from [source]. Used in
/// place of remote profile photos throughout MedRash (nickname preview chip,
/// leaderboard rows, profile header, etc.) to keep us aligned with the
/// nickname-only / no-PII pilot rule.
///
/// Initial extraction:
/// - Two-or-more words → first letter of first word + first letter of last word.
/// - Single word with camelcase capitals (e.g. `SwiftDoctor777`) → first two
///   uppercase letters (`SD`).
/// - Otherwise → first two characters, upper-cased.
/// - Empty / whitespace → `?`.
class MonogramAvatar extends StatelessWidget {
  const MonogramAvatar({
    super.key,
    required this.source,
    this.diameter = 48,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.borderWidth = 0,
    this.textStyle,
  });

  final String source;
  final double diameter;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double borderWidth;
  final TextStyle? textStyle;

  static String initialsFor(String source) {
    final String raw = source.trim();
    if (raw.isEmpty) return '?';
    final List<String> parts =
        raw.split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }
    final String caps = raw.replaceAll(RegExp(r'[^A-Z]'), '');
    if (caps.length >= 2) return caps.substring(0, 2);
    return raw.length >= 2
        ? raw.substring(0, 2).toUpperCase()
        : raw.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final Color bg = backgroundColor ?? tokens.secondary;
    final Color fg = foregroundColor ?? tokens.onSecondary;
    final TextStyle base =
        textStyle ?? Theme.of(context).textTheme.titleMedium ?? const TextStyle();
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: borderColor != null && borderWidth > 0
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initialsFor(source),
        style: base.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
