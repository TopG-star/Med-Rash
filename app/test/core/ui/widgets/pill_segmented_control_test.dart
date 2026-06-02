import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/pill_segmented_control.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );
}

void main() {
  group('PillSegmentedControl', () {
    testWidgets('renders all segment labels', (tester) async {
      await tester.pumpWidget(_host(PillSegmentedControl<String>(
        segments: const <PillSegment<String>>[
          PillSegment(value: 'top', label: 'Top'),
          PillSegment(value: 'quiz', label: 'Quiz'),
          PillSegment(value: 'cat', label: 'Categories'),
        ],
        value: 'top',
        onChanged: (_) {},
      )));
      expect(find.text('Top'), findsOneWidget);
      expect(find.text('Quiz'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
    });

    testWidgets('tapping a segment fires onChanged with its value',
        (tester) async {
      String? lastValue;
      await tester.pumpWidget(_host(PillSegmentedControl<String>(
        segments: const <PillSegment<String>>[
          PillSegment(value: 'a', label: 'A'),
          PillSegment(value: 'b', label: 'B'),
        ],
        value: 'a',
        onChanged: (String v) => lastValue = v,
      )));
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(lastValue, 'b');
    });
  });
}
