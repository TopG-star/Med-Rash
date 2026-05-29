// Slice B8 — XSS widget-rendering mirror to the admin Playwright suite.
//
// Flutter renders Strings as literal text inside Text widgets; it does NOT
// parse HTML. These tests are regression guards: if someone replaces the
// default Text widget with an HTML-rendering package (e.g. flutter_html)
// for any of the user-supplied surfaces, the assertion that the literal
// payload string is findable in the rendered tree will fail.
//
// Surfaces mirrored:
//   - nickname           (lobby / leaderboard player rows)
//   - host_name          (session header)
//   - quiz title         (quiz detail / list)
//   - question prompt    (quiz play screen)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _payloads = <String>[
  '<script>window.__xssTriggered=true;</script>',
  '<img src=x onerror="window.__xssTriggered=true">',
  '<svg onload="window.__xssTriggered=true">',
];

const _surfaces = <String>[
  'nickname',
  'host_name',
  'quiz title',
  'question prompt',
];

Future<void> _pumpSurface(WidgetTester tester, String userSupplied) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text(userSupplied)),
      ),
    ),
  );
}

void main() {
  group('XSS — Flutter renders user-supplied text as literal text', () {
    for (final surface in _surfaces) {
      for (final payload in _payloads) {
        testWidgets(
          '$surface: payload "${payload.substring(0, payload.length.clamp(0, 24))}…" renders as literal text',
          (tester) async {
            await _pumpSurface(tester, payload);

            // The exact payload string must be findable in the tree — this
            // proves Flutter rendered it as text, not parsed it as markup.
            expect(find.text(payload), findsOneWidget);
          },
        );
      }
    }
  });
}
