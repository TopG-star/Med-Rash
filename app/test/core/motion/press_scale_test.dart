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

  // Regression for the Slice 6e Vibrant Pulse rollout bug: when PressScale.onTap
  // is set AND the child is a Material button (FilledButton/ElevatedButton/etc.)
  // with its own onPressed, the two TapGestureRecognizers compete in the same
  // arena. Depending on framework version this either (a) fires both, (b) fires
  // neither, or (c) fires only one — silently swallowing user taps on the
  // affected screens (quiz_detail, recovery, profile, live, qr_scanner, runner,
  // result, session_join).
  //
  // The correct usage per PressScale's own docstring is to NOT pass `onTap`
  // when wrapping a widget that already has its own gesture (the Listener
  // alone drives the scale animation). This test asserts the inner button
  // fires reliably when PressScale is used that way (no onTap).
  testWidgets('inner Material button onPressed fires when PressScale has no onTap',
      (WidgetTester tester) async {
    int presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressScale(
              child: FilledButton(
                onPressed: () => presses++,
                child: const Text('Go Ranked'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go Ranked'));
    await tester.pumpAndSettle();
    expect(presses, 1,
        reason: 'with no PressScale.onTap, the inner FilledButton owns the gesture '
            'and onPressed must fire on every tap.');
  });

  // Characterization of the Slice 6e bug: when BOTH PressScale.onTap and the
  // inner Material button's onPressed are wired, exactly one of them must
  // fire (not zero, not both — duplicate fires are a problem too, because
  // they'd start two attempts on a single tap). This test pins the current
  // behaviour so any future refactor of PressScale's gesture handling is
  // forced to think about it.
  testWidgets('PressScale.onTap + inner FilledButton.onPressed does not silently swallow taps',
      (WidgetTester tester) async {
    int pressScaleTaps = 0;
    int buttonPresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressScale(
              onTap: () => pressScaleTaps++,
              child: FilledButton(
                onPressed: () => buttonPresses++,
                child: const Text('Start Learning'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start Learning'));
    await tester.pumpAndSettle();
    final int total = pressScaleTaps + buttonPresses;
    expect(total, 1,
        reason: 'Exactly one handler must fire — zero means the tap is silently '
            'swallowed (Slice 6e regression on quiz_detail/recovery/profile/live/'
            'qr_scanner/runner/result), two means the action runs twice.');
    // Diagnostic: which side wins the arena in the current Flutter version.
    // The inner FilledButton's InkResponse TapGestureRecognizer beats the
    // outer GestureDetector that PressScale wraps when onTap is non-null,
    // so it's the inner onPressed that actually runs. Pin this so any future
    // PressScale refactor that flips the resolution is caught loudly.
    expect(buttonPresses, 1,
        reason: 'The inner FilledButton wins the arena; PressScale.onTap is '
            'effectively dead code when wrapped around a Material button.');
    expect(pressScaleTaps, 0);
  });
}
