class Quiz {
  const Quiz({
    required this.id,
    required this.title,
    required this.category,
    required this.product,
    required this.description,
    required this.questionCount,
    required this.durationLabel,
    required this.difficulty,
  });

  final String id;
  final String title;
  final String category;
  final String product;
  final String description;
  final int questionCount;
  final String durationLabel;
  final String difficulty;
}