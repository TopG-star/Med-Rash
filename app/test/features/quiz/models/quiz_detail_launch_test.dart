import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/features/quiz/models/quiz_detail_launch.dart';
import 'package:medrash_app/features/quiz/repositories/quiz_repository.dart';

void main() {
  group('QuizDetailLaunch.fromExtra', () {
    test('returns the QuizDetailLaunch unchanged when passed one', () {
      const QuizDetailLaunch launch = QuizDetailLaunch(
        quizId: 'quiz-a',
        preselectedMode: QuizMode.learning,
      );
      expect(identical(QuizDetailLaunch.fromExtra(launch), launch), isTrue);
    });

    test('wraps a bare String quiz id with no preselected mode (back-compat)', () {
      final QuizDetailLaunch launch = QuizDetailLaunch.fromExtra('quiz-b');
      expect(launch.quizId, 'quiz-b');
      expect(launch.preselectedMode, isNull);
    });

    test('returns an empty launch for null / unknown extras', () {
      expect(QuizDetailLaunch.fromExtra(null).quizId, isNull);
      expect(QuizDetailLaunch.fromExtra(null).preselectedMode, isNull);
      expect(QuizDetailLaunch.fromExtra(42).quizId, isNull);
    });
  });
}
