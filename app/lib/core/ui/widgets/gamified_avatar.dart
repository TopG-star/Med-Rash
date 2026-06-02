import 'package:flutter/material.dart';

import '../../../features/profile/models/avatar_spec.dart';
import '../../theme/design_tokens.dart';
import '../../theme/theme_extensions.dart';
import 'monogram_avatar.dart';

/// Hero avatar used on Profile, Leaderboard podium, and Discover-friends
/// rows. Wraps an `AvatarSpec` body in a gradient ring (default = primary
/// header gradient) and supports an optional bottom-right flag emoji badge —
/// matching the gamified reference (UI 2 + UI 5).
///
/// The body switches on `AvatarSpec`:
/// * `MonogramAvatarSpec` → `MonogramAvatar` (current nickname-initials).
/// * `NaviiAvatarSpec`     → placeholder colored disc with a stylized glyph
///   until the Navii art pipeline ships.
class GamifiedAvatar extends StatelessWidget {
  const GamifiedAvatar({
    super.key,
    required this.spec,
    this.diameter = 96,
    this.ringWidth = 3,
    this.ringGradient,
    this.flagEmoji,
  });

  final AvatarSpec spec;
  final double diameter;
  final double ringWidth;

  /// Override the default ring gradient. When null the widget uses
  /// `MedRashGradient.primaryHeader(tokens)`.
  final Gradient? ringGradient;

  /// Optional country flag emoji rendered as a small circular badge at the
  /// bottom-right of the avatar.
  final String? flagEmoji;

  @override
  Widget build(BuildContext context) {
    final ArenaDesignTokens tokens = context.arenaTokens;
    final Gradient ring =
        ringGradient ?? MedRashGradient.primaryHeader(tokens);
    final double bodyDiameter = diameter - (ringWidth * 2);
    final double flagDiameter = diameter * 0.32;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: ring,
            ),
            alignment: Alignment.center,
            child: _buildBody(context, tokens, bodyDiameter),
          ),
          if (flagEmoji != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: flagDiameter,
                height: flagDiameter,
                decoration: BoxDecoration(
                  color: tokens.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: tokens.surface,
                    width: ringWidth,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  flagEmoji!,
                  style: TextStyle(fontSize: flagDiameter * 0.65),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ArenaDesignTokens tokens,
    double bodyDiameter,
  ) {
    switch (spec) {
      case MonogramAvatarSpec(:final String source, :final Color? tint):
        return MonogramAvatar(
          source: source,
          diameter: bodyDiameter,
          backgroundColor: tint ?? tokens.secondary,
          foregroundColor: tokens.onSecondary,
        );
      case NaviiAvatarSpec(
          :final Color bodyColor,
          :final Color accentColor,
          :final NaviiExpression expression
        ):
        return _NaviiPlaceholder(
          diameter: bodyDiameter,
          bodyColor: bodyColor,
          accentColor: accentColor,
          expression: expression,
        );
    }
  }
}

/// Temporary placeholder rendering for `NaviiAvatarSpec`. Draws a soft
/// disc using the player's chosen body color plus an accent ring; the
/// glyph in the center signals the chosen expression. Replaced by real
/// Navii art in a future phase.
class _NaviiPlaceholder extends StatelessWidget {
  const _NaviiPlaceholder({
    required this.diameter,
    required this.bodyColor,
    required this.accentColor,
    required this.expression,
  });

  final double diameter;
  final Color bodyColor;
  final Color accentColor;
  final NaviiExpression expression;

  @override
  Widget build(BuildContext context) {
    final String glyph = switch (expression) {
      NaviiExpression.smile => '\u{1F642}',
      NaviiExpression.focus => '\u{1F9D0}',
      NaviiExpression.cheer => '\u{1F389}',
      NaviiExpression.idle => '\u{1F4AC}',
    };
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: bodyColor,
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: diameter * 0.04),
      ),
      alignment: Alignment.center,
      child: Text(
        glyph,
        style: TextStyle(fontSize: diameter * 0.55),
      ),
    );
  }
}
