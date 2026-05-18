import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/features/leaderboard/repositories/leaderboard_repository.dart';

void main() {
  group('InMemoryLeaderboardRepository', () {
    test('fetchLeaderboard returns all-time rows ordered by rank', () async {
      final InMemoryLeaderboardRepository repository = InMemoryLeaderboardRepository();

      final rows = await repository.fetchLeaderboard(
        period: LeaderboardPeriod.allTime,
      );

      expect(rows.length, greaterThanOrEqualTo(3));
      expect(rows.first.rank, 1);
    });

    test('fetchLeaderboard respects the limit', () async {
      final InMemoryLeaderboardRepository repository = InMemoryLeaderboardRepository();

      final rows = await repository.fetchLeaderboard(
        period: LeaderboardPeriod.monthly,
        limit: 2,
      );

      expect(rows.length, 2);
    });

    test('fetchMyRank returns the row flagged as current user', () async {
      final InMemoryLeaderboardRepository repository = InMemoryLeaderboardRepository();

      final me = await repository.fetchMyRank(period: LeaderboardPeriod.allTime);

      expect(me, isNotNull);
      expect(me!.isCurrentUser, isTrue);
    });
  });
}
