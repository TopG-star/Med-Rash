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
}