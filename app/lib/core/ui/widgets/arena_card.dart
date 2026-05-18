import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

class ArenaCard extends StatelessWidget {
  const ArenaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;

    return Container(
      decoration: BoxDecoration(
        color: color ?? tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.outline, width: tokens.borderWidth),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            offset: Offset(tokens.shadowOffset, tokens.shadowOffset),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}