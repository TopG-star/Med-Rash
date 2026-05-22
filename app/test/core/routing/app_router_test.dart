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
}
