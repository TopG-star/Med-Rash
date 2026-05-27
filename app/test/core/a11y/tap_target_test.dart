import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';

void main() {
  group('Tap targets - WCAG 2.5.5 (>=44pt)', () {
    test('app theme leaves materialTapTargetSize at padded default', () {
      // padded default forces Material buttons / IconButtons to render with
      // a >=48dp hit area, comfortably above the 44pt WCAG target. Shrinking
      // to MaterialTapTargetSize.shrinkWrap would silently regress a11y, so
      // this guard fails fast if anyone overrides the theme.
      expect(AppTheme.light().materialTapTargetSize,
          MaterialTapTargetSize.padded);
    });

    testWidgets('default IconButton renders >=44pt tap area under app theme',
        (tester) async {
      final ThemeData theme = AppTheme.light();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {},
            ),
          ),
        ),
      ));
      final Size size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('default TextButton renders >=44pt tap area under app theme',
        (tester) async {
      final ThemeData theme = AppTheme.light();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: TextButton(onPressed: () {}, child: const Text('Resend')),
          ),
        ),
      ));
      final Size size = tester.getSize(find.byType(TextButton));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });
}
