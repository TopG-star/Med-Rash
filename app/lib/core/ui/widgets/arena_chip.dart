import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

class ArenaChip extends StatelessWidget {
  const ArenaChip({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color ?? tokens.secondary,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.outline, width: 2),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}