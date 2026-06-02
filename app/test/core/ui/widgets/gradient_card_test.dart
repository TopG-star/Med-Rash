import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/gradient_card.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('GradientCard', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(_host(const GradientCard(
        color: Color(0xFFFCD3CC),
        child: Text('Recent Quiz'),
      )));
      expect(find.text('Recent Quiz'), findsOneWidget);
    });

    testWidgets('onTap fires when tapped', (tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(GradientCard(
        color: const Color(0xFFC5BFF2),
        onTap: () => taps++,
        child: const SizedBox(width: 200, height: 80, child: Text('Featured')),
      )));
      await tester.tap(find.text('Featured'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('asserts when both gradient and color are provided',
        (tester) async {
      expect(
        () => GradientCard(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFF000000)],
          ),
          color: const Color(0xFFFCD3CC),
          child: const Text('bad'),
        ),
        throwsAssertionError,
      );
    });
  });
}
