import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/features/quiz/repositories/quiz_repository.dart';

Future<void> _completeAttempt(InMemoryQuizRepository repository) async {
  bool finished = false;
  while (!finished) {
    repository.selectAnswer(0);
    finished = await repository.submitCurrentAnswer();
  }
  await repository.finishAttempt();
}

void main() {
  group('InMemoryQuizRepository ranked attempt policy', () {
    test('blocks second ranked completion for the same quiz', () async {
      final InMemoryQuizRepository repository = InMemoryQuizRepository();
      const String quizId = 'clexane-vte-masterclass';

      expect(repository.canStartRankedAttempt(quizId), isTrue);

      await repository.startAttempt(quizId: quizId, mode: QuizMode.ranked);
      await _completeAttempt(repository);

      expect(repository.canStartRankedAttempt(quizId), isFalse);

      expect(
        () => repository.startAttempt(quizId: quizId, mode: QuizMode.ranked),
        throwsA(isA<StateError>()),
      );
    });

    test('allows repeated learning attempts for the same quiz', () async {
      final InMemoryQuizRepository repository = InMemoryQuizRepository();
      const String quizId = 'tavanic-infection-stewardship';

      await repository.startAttempt(quizId: quizId, mode: QuizMode.learning);
      await _completeAttempt(repository);

      await repository.startAttempt(quizId: quizId, mode: QuizMode.learning);
      await _completeAttempt(repository);

      expect(repository.canStartRankedAttempt(quizId), isTrue);
    });
  });
}

