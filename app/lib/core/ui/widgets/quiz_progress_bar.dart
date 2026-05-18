import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

class QuizProgressBar extends StatelessWidget {
  const QuizProgressBar({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.arenaTokens;
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.outline, width: tokens.borderWidth),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0, 1),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.primary,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}