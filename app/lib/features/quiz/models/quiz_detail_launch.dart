import '../repositories/quiz_repository.dart' show QuizMode;

/// Optional payload passed via `GoRoute.extra` when navigating to
/// `/quiz-detail`. Lets a caller (e.g. the Learn tab) preselect a mode so the
/// detail page can hide the other CTA and surface mode-specific messaging.
///
/// Back-compat: callers may still pass a bare `String` quiz id. Use
/// [QuizDetailLaunch.fromExtra] to normalise either form.
class QuizDetailLaunch {
  const QuizDetailLaunch({this.quizId, this.preselectedMode});

  final String? quizId;
  final QuizMode? preselectedMode;

  static QuizDetailLaunch fromExtra(Object? extra) {
    if (extra is QuizDetailLaunch) return extra;
    if (extra is String) return QuizDetailLaunch(quizId: extra);
    return const QuizDetailLaunch();
  }
}
