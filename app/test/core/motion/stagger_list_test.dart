import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medrash_app/core/motion/stagger_list.dart';

Widget _wrap(Widget child, {bool reducedMotion = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
}

void main() {
  testWidgets('staggers children in and reaches full opacity',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        StaggerList(
          itemDuration: const Duration(milliseconds: 100),
          itemDelay: const Duration(milliseconds: 50),
          children: List<Widget>.generate(
            3,
            (int i) => SizedBox(
              key: ValueKey<int>(i),
              width: 100,
              height: 40,
              child: Text('row $i'),
            ),
          ),
        ),
      ),
    );

    // Right after first frame, items are partially visible (low opacity).
    await tester.pump(const Duration(milliseconds: 16));
    final Iterable<Opacity> early = tester.widgetList<Opacity>(find.byType(Opacity));
    expect(early.length, 3);
    expect(early.first.opacity, lessThan(1.0));

    // After enough time for all delays + durations, all opacities reach 1.0.
    await tester.pump(const Duration(milliseconds: 800));
    final Iterable<Opacity> done = tester.widgetList<Opacity>(find.byType(Opacity));
    for (final Opacity o in done) {
      expect(o.opacity, closeTo(1.0, 0.001));
    }
  });

  testWidgets('reduced-motion shows every child fully on first frame',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        StaggerList(
          children: List<Widget>.generate(
            4,
            (int i) => SizedBox(width: 100, height: 40, child: Text('r$i')),
          ),
        ),
        reducedMotion: true,
      ),
    );

    await tester.pump();
    final Iterable<Opacity> os = tester.widgetList<Opacity>(find.byType(Opacity));
    expect(os.length, 4);
    for (final Opacity o in os) {
      expect(o.opacity, 1.0);
    }
  });
}
