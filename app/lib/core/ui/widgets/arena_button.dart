import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

class ArenaButton extends StatelessWidget {
  const ArenaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor ?? tokens.primary,
          foregroundColor: foregroundColor ?? tokens.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            side: BorderSide(color: tokens.outline, width: tokens.borderWidth),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon),
              const SizedBox(width: 12),
            ],
            Text(label, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}