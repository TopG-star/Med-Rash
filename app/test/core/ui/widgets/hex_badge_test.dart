import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/hex_badge.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('HexBadge', () {
    testWidgets('renders child centered', (tester) async {
      await tester.pumpWidget(_host(const HexBadge(
        size: 64,
        child: Text('B'),
      )));
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('honors size constraint', (tester) async {
      await tester.pumpWidget(_host(const HexBadge(
        size: 72,
        child: SizedBox.shrink(),
      )));
      final Size size = tester.getSize(find.byType(HexBadge));
      expect(size.width, 72);
      expect(size.height, 72);
    });
  });
}
