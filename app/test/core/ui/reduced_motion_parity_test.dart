import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/skeleton.dart';
import 'package:medrash_app/core/ui/widgets/quiz_progress_bar.dart';

Widget _wrap(Widget child, {required bool reducedMotion}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('Reduced-motion parity', () {
    testWidgets('MedRashSkeleton settles when disableAnimations=true',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const SizedBox(width: 120, child: MedRashSkeleton()),
            reducedMotion: true),
      );
      // With shimmer + pulse stopped the widget tree must reach a steady
      // state on the next frame — pump() would hang forever otherwise.
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('MedRashSkeleton animates when reduced-motion is off',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const SizedBox(width: 120, child: MedRashSkeleton()),
            reducedMotion: false),
      );
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.hasRunningAnimations, isTrue);
      // Drain the repeating animations so the test can tear down cleanly.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('QuizProgressBar tween is zero-duration under reduced motion',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const QuizProgressBar(progress: 0.4), reducedMotion: true),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
