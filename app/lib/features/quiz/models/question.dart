class Question {
  const Question({
    this.id,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    this.explanation,
  });

  /// Supabase UUID. Populated when questions come from the live quiz-list gate
  /// function. Null for InMemory stub questions.
  final String? id;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
}