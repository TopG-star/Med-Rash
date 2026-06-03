import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/config/app_config.dart';

void main() {
  group('AppConfig.validateOrThrow', () {
    test('accepts development environment with default localhost values', () {
      expect(() => AppConfig.validateOrThrow('development'), returnsNormally);
    });

    test('rejects non-development environment when defines are missing', () {
      // In `flutter test` runs no --dart-define is passed, so functionsBaseUrl
      // is still the localhost default and turnstileSiteKey is empty. That
      // exactly matches a misconfigured hosted build.
      expect(
        () => AppConfig.validateOrThrow('production'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => AppConfig.validateOrThrow('staging'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
