import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/features/quiz/qr/join_code_parser.dart';

void main() {
  group('parseJoinCodeFromQr', () {
    test('returns null for null, empty, and whitespace payloads', () {
      expect(parseJoinCodeFromQr(null), isNull);
      expect(parseJoinCodeFromQr(''), isNull);
      expect(parseJoinCodeFromQr('   '), isNull);
    });

    test('returns a trimmed bare join code unchanged', () {
      expect(parseJoinCodeFromQr('ABCD'), 'ABCD');
      expect(parseJoinCodeFromQr('  XYZ9  '), 'XYZ9');
    });

    test('rejects bare payloads that contain whitespace', () {
      expect(parseJoinCodeFromQr('AB CD'), isNull);
    });

    test('extracts the code from a /session/<code> deep link', () {
      expect(
        parseJoinCodeFromQr('https://medrash.app/session/ABCD'),
        'ABCD',
      );
    });

    test('decodes percent-escaped path segments', () {
      expect(
        parseJoinCodeFromQr('https://medrash.app/session/AB%20CD'),
        'AB CD',
      );
    });

    test('reads the code from `code` and `joinCode` query params', () {
      expect(
        parseJoinCodeFromQr('https://medrash.app/session?code=ABCD'),
        'ABCD',
      );
      expect(
        parseJoinCodeFromQr('https://medrash.app/session?joinCode=WXYZ'),
        'WXYZ',
      );
    });

    test('unwraps /join?next=/session/<code> redirect wrappers', () {
      expect(
        parseJoinCodeFromQr(
          'https://medrash.app/join?next=%2Fsession%2FABCD',
        ),
        'ABCD',
      );
    });

    test('returns null when the URL has no recoverable code', () {
      expect(
        parseJoinCodeFromQr('https://medrash.app/home'),
        isNull,
      );
    });
  });
}
