class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.name,
    required this.score,
    this.isCurrentUser = false,
    this.userId,
    this.rankedAttempts,
    this.lastRankedAt,
  });

  final int rank;
  final String name;
  final int score;
  final bool isCurrentUser;
  final String? userId;
  final int? rankedAttempts;
  final DateTime? lastRankedAt;

  LeaderboardRow copyWith({bool? isCurrentUser}) {
    return LeaderboardRow(
      rank: rank,
      name: name,
      score: score,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      userId: userId,
      rankedAttempts: rankedAttempts,
      lastRankedAt: lastRankedAt,
    );
  }
}