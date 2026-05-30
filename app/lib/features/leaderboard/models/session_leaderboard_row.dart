import 'leaderboard_row.dart';

/// One row in a session-scoped leaderboard. Distinct from [LeaderboardRow] so
/// the global vs per-session UIs can evolve independently — sessions surface
/// time-to-complete as a tiebreaker, which the global view doesn't display.
class SessionLeaderboardRow {
  const SessionLeaderboardRow({
    required this.rank,
    required this.userId,
    required this.name,
    required this.sessionScore,
    required this.timeTakenMs,
    this.completedAt,
    this.isCurrentUser = false,
  });

  final int rank;
  final String userId;
  final String name;
  final int sessionScore;
  final int timeTakenMs;
  final DateTime? completedAt;
  final bool isCurrentUser;

  SessionLeaderboardRow copyWith({bool? isCurrentUser}) {
    return SessionLeaderboardRow(
      rank: rank,
      userId: userId,
      name: name,
      sessionScore: sessionScore,
      timeTakenMs: timeTakenMs,
      completedAt: completedAt,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
    );
  }

  /// Convenience adapter so the existing leaderboard list widgets (built
  /// around [LeaderboardRow]) can render session boards without a parallel UI.
  LeaderboardRow toLeaderboardRow() {
    return LeaderboardRow(
      rank: rank,
      name: name,
      score: sessionScore,
      isCurrentUser: isCurrentUser,
      userId: userId,
    );
  }
}

/// Result envelope for a session-leaderboard poll. [isLive] tells the UI
/// whether to keep polling; once false the screen freezes the table.
class SessionLeaderboardResult {
  const SessionLeaderboardResult({
    required this.sessionId,
    required this.isLive,
    required this.rows,
    required this.requestingUserId,
    this.me,
    this.endsAt,
    this.closedAt,
    this.notAParticipant = false,
  });

  final String sessionId;
  final bool isLive;
  final List<SessionLeaderboardRow> rows;
  final SessionLeaderboardRow? me;
  final String? requestingUserId;
  final DateTime? endsAt;
  final DateTime? closedAt;

  /// True when the server returned NOT_SESSION_PARTICIPANT — the requester
  /// hasn't played this session yet. UI surfaces a "Play first" empty state.
  final bool notAParticipant;
}
