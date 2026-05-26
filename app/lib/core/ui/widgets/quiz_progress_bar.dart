import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// Quiz progress bar — purple→gold gradient fill that animates between
/// progress values. Honours `MediaQuery.disableAnimations` (snaps instantly
/// when reduced motion is requested).
class QuizProgressBar extends StatelessWidget {
  const QuizProgressBar({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    final bool reducedMotion = MediaQuery.of(context).disableAnimations;
    final double clamped = progress.clamp(0.0, 1.0).toDouble();

    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.outline, width: tokens.borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: TweenAnimationBuilder<double>(
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: clamped, end: clamped),
        builder: (BuildContext context, double value, Widget? _) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[tokens.primary, tokens.secondary],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        },
      ),
    );
  }
}
