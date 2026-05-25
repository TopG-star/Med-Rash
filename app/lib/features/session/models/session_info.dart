class SessionInfo {
  const SessionInfo({
    this.sessionId,
    this.joinCode,
    required this.quizId,
    required this.title,
    required this.category,
    required this.topic,
    required this.questionCount,
    required this.timeLimit,
    required this.host,
    this.mode = 'ranked',
  });

  final String? sessionId;
  final String? joinCode;
  final String quizId;
  final String title;
  final String category;
  final String topic;
  final int questionCount;
  final String timeLimit;
  final String host;

  /// Host-declared session intent: `'ranked'` (single official attempt that
  /// counts on the leaderboard) or `'learning'` (unlimited practice, no
  /// leaderboard impact). Set by the admin at session-create time; the
  /// participant lobby renders a single primary CTA based on this value.
  /// Defaults to `'ranked'` for backward compatibility with sessions that
  /// pre-date the [011_session_mode] migration.
  final String mode;
}