import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/stat_ring.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('StatRing', () {
    testWidgets('renders child label in center', (tester) async {
      await tester.pumpWidget(_host(const StatRing(
        progress: 0.5,
        diameter: 120,
        child: Text('37/50'),
      )));
      expect(find.text('37/50'), findsOneWidget);
    });

    testWidgets('handles out-of-range progress without throwing',
        (tester) async {
      // Clamping is internal; values outside 0..1 must not crash paint.
      await tester.pumpWidget(_host(const StatRing(
        progress: -0.5,
        diameter: 80,
      )));
      await tester.pumpWidget(_host(const StatRing(
        progress: 2.0,
        diameter: 80,
      )));
      // No exceptions thrown — implicit assertion.
      expect(tester.takeException(), isNull);
    });

    testWidgets('honors diameter constraint', (tester) async {
      await tester.pumpWidget(_host(const StatRing(
        progress: 0.75,
        diameter: 100,
      )));
      final Size size = tester.getSize(find.byType(StatRing));
      expect(size, const Size(100, 100));
    });
  });
}
