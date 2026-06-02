class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.name,
    required this.score,
    this.isCurrentUser = false,
    this.userId,
    this.seed,
    this.rankedAttempts,
    this.lastRankedAt,
  });

  final int rank;
  final String name;
  final int score;
  final bool isCurrentUser;
  final String? userId;

  /// P7.5 — stable Navii avatar seed (= `identity_spine_id` /
  /// participantId). Distinct from [userId] (which is the server-side
  /// `users.id` PK). When null the avatar widget falls back to [userId]
  /// to preserve mascot determinism on legacy rows.
  final String? seed;
  final int? rankedAttempts;
  final DateTime? lastRankedAt;

  LeaderboardRow copyWith({bool? isCurrentUser}) {
    return LeaderboardRow(
      rank: rank,
      name: name,
      score: score,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      userId: userId,
      seed: seed,
      rankedAttempts: rankedAttempts,
      lastRankedAt: lastRankedAt,
    );
  }
}