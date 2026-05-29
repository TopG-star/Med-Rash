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
    final bool disabled = onPressed == null;

    final Color enabledBg = backgroundColor ?? tokens.primary;
    final Color enabledFg = foregroundColor ?? tokens.textPrimary;
    // Disabled visuals: muted surface + muted text + muted border so a button
    // that cannot be tapped is unmistakably non-actionable. Avoids the
    // "looks tappable but isn't" trap (e.g. ranked-attempt-used CTA).
    final Color disabledBg = tokens.surfaceMuted;
    final Color disabledFg = tokens.textSecondary.withValues(alpha: 0.7);
    final Color borderColor =
        disabled ? tokens.outlineMuted : tokens.outline;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: enabledBg,
          foregroundColor: enabledFg,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            side: BorderSide(color: borderColor, width: tokens.borderWidth),
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