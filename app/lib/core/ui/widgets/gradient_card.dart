import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// Rounded card with optional gradient fill, used for Featured / Recent
/// Quiz / Live tiles on Home and Discover. Distinct from `ArenaCard` which
/// is a flat surface card — `GradientCard` pairs with the pastel card
/// tokens (`cardPeach`, `cardLavender`, `cardMint`, `cardGold`) or with a
/// full gradient for hero tiles.
///
/// Provide either [gradient] or [color] — not both. If neither is set,
/// `tokens.surface` is used.
class GradientCard extends StatelessWidget {
  const GradientCard({
    super.key,
    required this.child,
    this.gradient,
    this.color,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
  }) : assert(
          gradient == null || color == null,
          'Provide gradient OR color, not both',
        );

  final Widget child;
  final Gradient? gradient;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final BorderRadius radius = BorderRadius.circular(tokens.radiusLarge);
    final Decoration decoration = BoxDecoration(
      gradient: gradient,
      color: gradient == null ? (color ?? tokens.surface) : null,
      borderRadius: radius,
      border: Border.all(
        color: borderColor ?? tokens.outline,
        width: tokens.borderWidth,
      ),
    );

    final Widget content = Container(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: content,
      ),
    );
  }
}
