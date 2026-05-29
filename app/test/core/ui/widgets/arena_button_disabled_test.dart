import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/theme/app_theme.dart';
import 'package:medrash_app/core/theme/design_tokens.dart';
import 'package:medrash_app/core/theme/theme_extensions.dart';
import 'package:medrash_app/core/ui/widgets/arena_button.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('ArenaButton disabled state', () {
    testWidgets('tap is ignored when onPressed is null', (tester) async {
      int taps = 0;
      // Wrap in a GestureDetector to prove the FilledButton swallows nothing
      // additional when disabled — taps simply never reach the handler.
      await tester.pumpWidget(_host(
        const ArenaButton(label: 'Disabled', onPressed: null),
      ));

      await tester.tap(find.text('Disabled'));
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('renders muted background + muted foreground when disabled',
        (tester) async {
      ArenaDesignTokens? capturedTokens;
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) {
            capturedTokens = context.arenaTokens;
            return const ArenaButton(label: 'Disabled', onPressed: null);
          },
        ),
      ));

      final tokens = capturedTokens!;
      final FilledButton button = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      final ButtonStyle style = button.style!;

      final Color? bg = style.backgroundColor?.resolve(
        <WidgetState>{WidgetState.disabled},
      );
      final Color? fg = style.foregroundColor?.resolve(
        <WidgetState>{WidgetState.disabled},
      );

      expect(bg, tokens.surfaceMuted,
          reason: 'Disabled background must use surfaceMuted token.');
      expect(fg, tokens.textSecondary.withValues(alpha: 0.7),
          reason: 'Disabled foreground must use muted textSecondary.');
    });

    testWidgets('renders primary background when enabled', (tester) async {
      ArenaDesignTokens? capturedTokens;
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) {
            capturedTokens = context.arenaTokens;
            return ArenaButton(label: 'Enabled', onPressed: () {});
          },
        ),
      ));

      final tokens = capturedTokens!;
      final FilledButton button = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      final Color? bg = button.style!.backgroundColor?.resolve(<WidgetState>{});

      expect(bg, tokens.primary);
    });
  });
}
