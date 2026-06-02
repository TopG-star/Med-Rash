import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/ui/widgets/gamified_avatar.dart';
import 'package:medrash_app/core/ui/widgets/monogram_avatar.dart';
import 'package:medrash_app/features/profile/models/avatar_spec.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('GamifiedAvatar', () {
    testWidgets('MonogramAvatarSpec renders MonogramAvatar body', (tester) async {
      await tester.pumpWidget(_host(const GamifiedAvatar(
        spec: MonogramAvatarSpec(source: 'John Kofi'),
        diameter: 80,
      )));
      expect(find.byType(MonogramAvatar), findsOneWidget);
      expect(find.text('JK'), findsOneWidget);
    });

    testWidgets('NaviiAvatarSpec renders placeholder glyph for expression',
        (tester) async {
      await tester.pumpWidget(_host(const GamifiedAvatar(
        spec: NaviiAvatarSpec(
          bodyColor: Color(0xFF6C5CE7),
          accentColor: Color(0xFFFFC329),
          expression: NaviiExpression.cheer,
        ),
        diameter: 80,
      )));
      // Cheer maps to the party-popper glyph; presence confirms the switch.
      expect(find.text('\u{1F389}'), findsOneWidget);
      expect(find.byType(MonogramAvatar), findsNothing);
    });

    testWidgets('flagEmoji renders only when provided', (tester) async {
      await tester.pumpWidget(_host(const GamifiedAvatar(
        spec: MonogramAvatarSpec(source: 'AB'),
        diameter: 80,
        flagEmoji: '\u{1F1EC}\u{1F1ED}',
      )));
      expect(find.text('\u{1F1EC}\u{1F1ED}'), findsOneWidget);
    });

    testWidgets('flag absent when flagEmoji is null', (tester) async {
      await tester.pumpWidget(_host(const GamifiedAvatar(
        spec: MonogramAvatarSpec(source: 'AB'),
        diameter: 80,
      )));
      // No flag text rendered. Only the monogram initials.
      expect(find.text('AB'), findsOneWidget);
      expect(find.text('\u{1F1EC}\u{1F1ED}'), findsNothing);
    });
  });
}
