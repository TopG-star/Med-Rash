import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../theme/theme_extensions.dart';

/// Podium tier — drives the gradient stops and the numeral foreground.
enum PodiumTier { gold, silver, bronze }

/// Single riser on a 3-up leaderboard podium (UI 5 reference).
///
/// Renders a rounded-top column filled with the tier gradient from
/// `MedRashGradient`, with the rank numeral centered. Foreground is fixed
/// per-tier so it stays AA-readable in both light and dark themes:
/// * gold/silver use a fixed dark numeral (gold/silver are decorative
///   metallic colors that don't theme-follow),
/// * bronze uses white.
class PodiumBlock extends StatelessWidget {
  const PodiumBlock({
    super.key,
    required this.tier,
    required this.height,
    required this.rankNumeral,
    this.width = 96,
    this.label,
  });

  final PodiumTier tier;
  final double height;
  final int rankNumeral;
  final double width;

  /// Optional label rendered below the numeral (e.g. "QP 1,234").
  final String? label;

  /// Foreground numeral color asserted in the WCAG suite. Must stay in sync
  /// with `design_tokens_contrast_test.dart`'s `podiumDarkNumeral`.
  static const Color _darkNumeral = Color(0xFF1E1A2E);

  @override
  Widget build(BuildContext context) {
    final ArenaDesignTokens tokens = context.arenaTokens;
    final LinearGradient gradient = switch (tier) {
      PodiumTier.gold => MedRashGradient.podiumGold(tokens),
      PodiumTier.silver => MedRashGradient.podiumSilver(tokens),
      PodiumTier.bronze => MedRashGradient.podiumBronze(tokens),
    };
    final Color fg = switch (tier) {
      PodiumTier.gold => _darkNumeral,
      PodiumTier.silver => _darkNumeral,
      PodiumTier.bronze => Colors.white,
    };
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radiusLarge),
        ),
        border: Border.all(color: tokens.outline, width: tokens.borderWidth),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '$rankNumeral',
            style: (text.displayMedium ?? const TextStyle()).copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          if (label != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              label!,
              style: (text.labelMedium ?? const TextStyle()).copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
