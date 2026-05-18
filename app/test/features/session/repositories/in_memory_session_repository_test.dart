import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/features/session/repositories/session_repository.dart';

void main() {
  group('InMemorySessionRepository join code resolution', () {
    test('returns featured session for matching join code', () async {
      final InMemorySessionRepository repository = InMemorySessionRepository();

      final session = await repository.resolveSessionByJoinCode('KBTH-CME-2026');

      expect(session.quizId, 'clexane-vte-masterclass');
      expect(session.title, 'Korle Bu CME - VTE Master Class');
    });

    test('throws when join code does not exist', () async {
      final InMemorySessionRepository repository = InMemorySessionRepository();

      expect(
        () => repository.resolveSessionByJoinCode('UNKNOWN-CODE'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
