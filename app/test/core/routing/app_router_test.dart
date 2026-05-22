import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/routing/app_router.dart';

void main() {
  group('safeNextPath', () {
    test('accepts a simple in-app path', () {
      expect(safeNextPath('/home'), '/home');
      expect(safeNextPath('/session/ABCD'), '/session/ABCD');
      expect(safeNextPath('/leaderboard?period=allTime'),
          '/leaderboard?period=allTime');
    });

    test('rejects null, empty, and non-rooted paths', () {
      expect(safeNextPath(null), isNull);
      expect(safeNextPath(''), isNull);
      expect(safeNextPath('home'), isNull);
      expect(safeNextPath('session/ABCD'), isNull);
    });

    test('rejects scheme-relative and absolute URLs '
        '(open-redirect defence)', () {
      expect(safeNextPath('//evil.test/phish'), isNull);
      expect(safeNextPath('https://evil.test/phish'), isNull);
      expect(safeNextPath('javascript:alert(1)'), isNull);
      expect(safeNextPath('http://example.test'), isNull);
    });
  });

  group('joinCodeFromNextPath', () {
    test('extracts code from /session/<code>', () {
      expect(joinCodeFromNextPath('/session/ABCD'), 'ABCD');
      expect(joinCodeFromNextPath('/session/KBTH-CME-2026'), 'KBTH-CME-2026');
    });

    test('strips trailing slash, query, and fragment', () {
      expect(joinCodeFromNextPath('/session/ABCD/'), 'ABCD');
      expect(joinCodeFromNextPath('/session/ABCD?x=1'), 'ABCD');
      expect(joinCodeFromNextPath('/session/ABCD#frag'), 'ABCD');
    });

    test('decodes percent-encoded codes', () {
      expect(joinCodeFromNextPath('/session/A%20B'), 'A B');
    });

    test('returns null for non-session paths and empty codes', () {
      expect(joinCodeFromNextPath(null), isNull);
      expect(joinCodeFromNextPath(''), isNull);
      expect(joinCodeFromNextPath('/home'), isNull);
      expect(joinCodeFromNextPath('/sessions'), isNull);
      expect(joinCodeFromNextPath('/session/'), isNull);
    });
  });

  group('main.dart wiring', () {
    test('calls usePathUrlStrategy() so clean QR/deep links reach go_router',
        () {
      // Hash strategy strips /session/<code> before go_router sees it, which
      // silently sends QR scans to /home (Mode Selection). Lock the fix at
      // the source so it cannot regress.
      final String source = File('lib/main.dart').readAsStringSync();
      expect(
        source.contains('usePathUrlStrategy()'),
        isTrue,
        reason: 'main.dart must call usePathUrlStrategy() before runApp.',
      );
      expect(
        source.contains(
            "import 'package:flutter_web_plugins/url_strategy.dart'"),
        isTrue,
        reason: 'main.dart must import the url_strategy plugin.',
      );
    });
  });
}
