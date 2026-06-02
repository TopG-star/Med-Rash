import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/podium_block.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('PodiumBlock', () {
    testWidgets('renders rank numeral and optional label', (tester) async {
      await tester.pumpWidget(_host(const PodiumBlock(
        tier: PodiumTier.gold,
        height: 160,
        rankNumeral: 1,
        label: 'QP 1,234',
      )));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('QP 1,234'), findsOneWidget);
    });

    testWidgets('label is omitted when null', (tester) async {
      await tester.pumpWidget(_host(const PodiumBlock(
        tier: PodiumTier.silver,
        height: 120,
        rankNumeral: 2,
      )));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('QP 1,234'), findsNothing);
    });

    testWidgets('honors width and height constraints', (tester) async {
      await tester.pumpWidget(_host(const PodiumBlock(
        tier: PodiumTier.bronze,
        height: 100,
        rankNumeral: 3,
        width: 80,
      )));
      final Size size = tester.getSize(find.byType(PodiumBlock));
      expect(size, const Size(80, 100));
    });
  });
}
