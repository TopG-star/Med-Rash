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

    testWidgets('NaviiAvatarSpec falls back to monogram when flag is off',
        (tester) async {
      await tester.pumpWidget(_host(const GamifiedAvatar(
        spec: NaviiAvatarSpec(
          seed: '11111111-2222-3333-4444-555555555555',
          fallbackSource: 'Ada Lovelace',
        ),
        diameter: 80,
      )));
      // Feature flag defaults to off in the test binary, so the Navii
      // branch short-circuits to the monogram fallback.
      expect(find.byType(MonogramAvatar), findsOneWidget);
      expect(find.text('AL'), findsOneWidget);
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
