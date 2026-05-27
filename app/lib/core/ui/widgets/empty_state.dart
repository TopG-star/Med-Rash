import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../theme/theme_extensions.dart';
import 'arena_button.dart';
import 'arena_card.dart';

/// Reusable Vibrant Pulse empty-state card: gradient icon ring, headline,
/// supporting copy, and an optional primary CTA. Used wherever a list/board
/// is empty on first-pilot-session devices (no rankings yet, no active
/// quizzes, no ranked attempts logged).
class MedRashEmptyState extends StatelessWidget {
  const MedRashEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
    this.padding = const EdgeInsets.all(MedRashSpace.xl),
  });

  final IconData icon;
  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool hasCta = ctaLabel != null && onCta != null;
    return ArenaCard(
      padding: padding,
      child: Column(
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  tokens.primary.withValues(alpha: 0.18),
                  tokens.secondary.withValues(alpha: 0.22),
                ],
              ),
              border: Border.all(
                color: tokens.outline,
                width: tokens.borderWidth,
              ),
            ),
            child: Icon(
              icon,
              color: tokens.primary,
              size: MedRashIconSize.xl,
            ),
          ),
          const SizedBox(height: MedRashSpace.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
          ),
          const SizedBox(height: MedRashSpace.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
          ),
          if (hasCta) ...<Widget>[
            const SizedBox(height: MedRashSpace.lg),
            ArenaButton(
              label: ctaLabel!,
              onPressed: onCta,
              // In dark mode `primary` is a light lilac; pair white with the
              // darker `primarySoft` surface there so the CTA stays WCAG AA
              // legible (matches the badge-unlocked snackbar contract).
              backgroundColor:
                  Theme.of(context).brightness == Brightness.dark
                      ? tokens.primarySoft
                      : tokens.primary,
              foregroundColor: Colors.white,
            ),
          ],
        ],
      ),
    );
  }
}
