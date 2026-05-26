import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medrash_app/core/motion/count_up_number.dart';

Widget _wrap(Widget child, {bool reducedMotion = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
}

int _renderedInt(WidgetTester tester) {
  return int.parse((tester.widget(find.byType(Text)) as Text).data!);
}

void main() {
  testWidgets('animates from 0 to the target value',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const CountUpNumber(
          value: 120,
          duration: Duration(milliseconds: 200),
        ),
      ),
    );

    expect(_renderedInt(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    final int mid = _renderedInt(tester);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(120));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_renderedInt(tester), 120);
  });

  testWidgets('reduced-motion renders the final value immediately',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const CountUpNumber(
          value: 999,
          duration: Duration(milliseconds: 500),
        ),
        reducedMotion: true,
      ),
    );

    expect(_renderedInt(tester), 999);
  });

  testWidgets('uses formatter when provided', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        CountUpNumber(
          value: 1234,
          formatter: (int n) => '$n pts',
        ),
        reducedMotion: true,
      ),
    );

    expect((tester.widget(find.byType(Text)) as Text).data, '1234 pts');
  });
}
