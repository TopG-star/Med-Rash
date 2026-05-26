import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medrash_app/core/motion/press_scale.dart';

Future<Widget> _wrap(Widget child, {bool reducedMotion = false}) async {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
}

double _currentScale(WidgetTester tester) {
  final Transform t = tester.widget(find.byType(Transform).first);
  // Matrix4 scaleX lives at row 0, col 0.
  return t.transform.entry(0, 0);
}

void main() {
  testWidgets('scales down on pointer-down and back on pointer-up',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      await _wrap(
        const PressScale(
          pressedScale: 0.9,
          child: SizedBox(width: 100, height: 100),
        ),
      ),
    );

    expect(_currentScale(tester), 1.0);

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_currentScale(tester), closeTo(0.9, 0.001));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_currentScale(tester), closeTo(1.0, 0.001));
  });

  testWidgets('fires onTap when wrapped as a button',
      (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      await _wrap(
        PressScale(
          onTap: () => taps++,
          child: const SizedBox(width: 80, height: 80),
        ),
      ),
    );

    await tester.tap(find.byType(PressScale));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('reduced-motion disables the scale animation',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      await _wrap(
        const PressScale(
          pressedScale: 0.85,
          child: SizedBox(width: 100, height: 100),
        ),
        reducedMotion: true,
      ),
    );

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_currentScale(tester), 1.0,
        reason: 'reduced-motion should keep scale at rest');
    await gesture.up();
  });
}
