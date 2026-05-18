class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.name,
    required this.score,
    this.isCurrentUser = false,
  });

  final int rank;
  final String name;
  final int score;
  final bool isCurrentUser;
}