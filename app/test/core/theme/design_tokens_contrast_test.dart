import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/design_tokens.dart';

/// WCAG 2.1 contrast audit for the Vibrant Pulse palette (Slice 6a).
///
/// Thresholds:
/// * 4.5:1 for body text (small / normal weight).
/// * 3.0:1 for large text (>=18pt regular or >=14pt bold) and meaningful
///   non-text UI (icon glyphs, button fills).
///
/// Decorative outlines that don't carry information (card borders that
/// rely on fill + shadow for definition) are intentionally not asserted
/// here per WCAG SC 1.4.11.
void main() {
  group('ArenaDesignTokens - WCAG AA contrast', () {
    _runSuite('light', ArenaDesignTokens.light, isDark: false);
    _runSuite('dark', ArenaDesignTokens.dark, isDark: true);
  });
}

void _runSuite(String label, ArenaDesignTokens t, {required bool isDark}) {
  group(label, () {
    _expectAA('textPrimary on background', t.textPrimary, t.background);
    _expectAA('textPrimary on surface', t.textPrimary, t.surface);
    _expectAA('textPrimary on surfaceMuted', t.textPrimary, t.surfaceMuted);
    _expectAA(
        'textPrimary on surfaceContainer', t.textPrimary, t.surfaceContainer);
    _expectAA('textSecondary on background', t.textSecondary, t.background);
    _expectAA('textSecondary on surface', t.textSecondary, t.surface);
    _expectAA('textSecondary on surfaceMuted', t.textSecondary, t.surfaceMuted);

    // The badge-unlocked snackbar (quiz_result_page._onBadgeUnlocked) and the
    // shared MedRashEmptyState CTA both pair white with the darker accent
    // surface - primaryStrong in light, primarySoft in dark - to stay AA.
    final Color darkAccent = isDark ? t.primarySoft : t.primaryStrong;
    _expectAA(
        'white on dark accent (badge unlocked toast)', Colors.white, darkAccent);
    _expectAA('onSecondary on secondary', t.onSecondary, t.secondary);
    _expectAA(
        'onSecondary on secondaryStrong', t.onSecondary, t.secondaryStrong);

    // success/error tokens appear as ICON glyphs (cloud_done, check, close)
    // on their tinted surfaces — body text on these surfaces always uses
    // textPrimary. Hence the AA-large (3:1) threshold per WCAG SC 1.4.11.
    _expectAALarge(
        'success glyph on successSurface', t.success, t.successSurface);
    _expectAALarge('error glyph on dangerSurface', t.error, t.dangerSurface);

    _expectAALarge('primary glyph on background', t.primary, t.background);
    _expectAALarge('primary glyph on surface', t.primary, t.surface);
    _expectAALarge(
        'white glyph on dark accent CTA fill', Colors.white, darkAccent);
  });
}

void _expectAA(String pairing, Color fg, Color bg) {
  test(pairing, () {
    final double ratio = _contrastRatio(fg, bg);
    expect(
      ratio,
      greaterThanOrEqualTo(4.5),
      reason:
          '$pairing must meet WCAG AA body-text contrast (>=4.5:1) - measured ${ratio.toStringAsFixed(2)}:1.',
    );
  });
}

void _expectAALarge(String pairing, Color fg, Color bg) {
  test(pairing, () {
    final double ratio = _contrastRatio(fg, bg);
    expect(
      ratio,
      greaterThanOrEqualTo(3.0),
      reason:
          '$pairing must meet WCAG AA large-text / non-text contrast (>=3.0:1) - measured ${ratio.toStringAsFixed(2)}:1.',
    );
  });
}

double _contrastRatio(Color fg, Color bg) {
  final double l1 = _relativeLuminance(fg);
  final double l2 = _relativeLuminance(bg);
  final double lighter = math.max(l1, l2);
  final double darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color c) {
  final double r = _channel(c.r);
  final double g = _channel(c.g);
  final double b = _channel(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _channel(double v) {
  // `Color.r/g/b` return 0..1 linearized components in Flutter >= 3.27.
  return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
}
