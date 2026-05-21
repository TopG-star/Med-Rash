class Attempt {
  const Attempt({
    required this.score,
    required this.totalQuestions,
    required this.timeLabel,
    required this.modeLabel,
    required this.timeTakenMs,
  });

  final int score;
  final int totalQuestions;
  final String timeLabel;
  final String modeLabel;
  final int timeTakenMs;
}