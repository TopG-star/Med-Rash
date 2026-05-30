import '../models/leaderboard_row.dart';
import '../models/session_leaderboard_row.dart';

enum LeaderboardPeriod { monthly, allTime }

abstract class LeaderboardRepository {
  Future<List<LeaderboardRow>> fetchLeaderboard({
    required LeaderboardPeriod period,
    int limit = 50,
    String? season,
  });

  Future<LeaderboardRow?> fetchMyRank({
    required LeaderboardPeriod period,
    String? season,
  });

  /// Live (or recently-ended) leaderboard for a single session. Distinct
  /// transport from the global leaderboard because access is gated to
  /// participants who have at least one attempt row in this session.
  Future<SessionLeaderboardResult> fetchSessionLeaderboard({
    required String sessionId,
    int limit = 50,
  });
}

class InMemoryLeaderboardRepository implements LeaderboardRepository {
  static const List<LeaderboardRow> _allTimeRows = <LeaderboardRow>[
    LeaderboardRow(rank: 1, name: 'Setor', score: 22200),
    LeaderboardRow(rank: 2, name: 'Papa Ekow', score: 11807),
    LeaderboardRow(rank: 3, name: 'eddykay7', score: 11338),
    LeaderboardRow(rank: 4, name: 'rpsjosh', score: 9088, isCurrentUser: true),
    LeaderboardRow(rank: 5, name: 'LordRa', score: 2566),
    LeaderboardRow(rank: 6, name: 'Ssstylar', score: 2100),
    LeaderboardRow(rank: 7, name: 'haadi', score: 1710),
    LeaderboardRow(rank: 8, name: 'manuelson', score: 684),
  ];

  static const List<LeaderboardRow> _monthlyRows = <LeaderboardRow>[
    LeaderboardRow(rank: 1, name: 'rpsjosh', score: 1200, isCurrentUser: true),
    LeaderboardRow(rank: 2, name: 'Setor', score: 1100),
    LeaderboardRow(rank: 3, name: 'Papa Ekow', score: 1020),
    LeaderboardRow(rank: 4, name: 'eddykay7', score: 980),
    LeaderboardRow(rank: 5, name: 'LordRa', score: 720),
  ];

  @override
  Future<List<LeaderboardRow>> fetchLeaderboard({
    required LeaderboardPeriod period,
    int limit = 50,
    String? season,
  }) async {
    final List<LeaderboardRow> rows =
        period == LeaderboardPeriod.allTime ? _allTimeRows : _monthlyRows;
    if (limit <= 0) {
      return <LeaderboardRow>[];
    }
    return rows.take(limit).toList();
  }

  @override
  Future<LeaderboardRow?> fetchMyRank({
    required LeaderboardPeriod period,
    String? season,
  }) async {
    final List<LeaderboardRow> rows =
        period == LeaderboardPeriod.allTime ? _allTimeRows : _monthlyRows;
    for (final LeaderboardRow row in rows) {
      if (row.isCurrentUser) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<SessionLeaderboardResult> fetchSessionLeaderboard({
    required String sessionId,
    int limit = 50,
  }) async {
    // The in-memory fallback intentionally returns the "not a participant"
    // shape so screens degrade gracefully in offline/seed mode rather than
    // pretending the user has a live session running.
    return SessionLeaderboardResult(
      sessionId: sessionId,
      isLive: false,
      rows: const <SessionLeaderboardRow>[],
      requestingUserId: null,
      notAParticipant: true,
    );
  }
}