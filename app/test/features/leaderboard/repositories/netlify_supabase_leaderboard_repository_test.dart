import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medrash_app/core/events/medrash_events.dart';
import 'package:medrash_app/core/infra/auth_state_manager.dart';
import 'package:medrash_app/core/infra/device_identity_service.dart';
import 'package:medrash_app/core/infra/event_bus.dart';
import 'package:medrash_app/core/infra/identity_snapshot.dart';
import 'package:medrash_app/core/infra/identity_spine.dart';
import 'package:medrash_app/core/infra/medrash_http_client.dart';
import 'package:medrash_app/features/leaderboard/repositories/leaderboard_repository.dart';
import 'package:medrash_app/features/leaderboard/repositories/netlify_supabase_leaderboard_repository.dart';
import 'package:medrash_app/features/leaderboard/models/leaderboard_row.dart';
import 'package:medrash_app/features/profile/models/user_profile.dart';
import 'package:medrash_app/features/profile/repositories/profile_repository.dart';

/// Regression coverage for the participant-side "All-Time total points" bug.
///
/// The server-of-record (`app.ranked_attempt_totals_all_time`) sums `score`
/// across every ranked attempt for a user, so a ranked attempt on a different
/// quiz should grow the total. On the client, the only way that growth can
/// fail to appear is if the leaderboard repo serves a stale cached snapshot
/// after an [AttemptSubmittedEvent]. This test pins that contract.
void main() {
  group('NetlifySupabaseLeaderboardRepository cache invalidation', () {
    test('refetches after AttemptSubmittedEvent so a new ranked attempt on '
        'a different quiz grows the total', () async {
      int hitCount = 0;
      int totalScoreToReturn = 5;

      final http.Client mockHttp = MockClient((http.Request request) async {
        hitCount += 1;
        return http.Response(
          jsonEncode(<String, Object?>{
            'top': <Map<String, Object?>>[
              <String, Object?>{
                'rank': 1,
                'nickname': 'TestUser',
                'totalScore': totalScoreToReturn,
                'rankedAttempts': hitCount,
              },
            ],
            'me': null,
            'seasonKey': null,
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final MedRashHttpClient httpClient = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mockHttp,
      );

      final EventBus eventBus = EventBus();
      final NetlifySupabaseLeaderboardRepository repo =
          NetlifySupabaseLeaderboardRepository(
        httpClient: httpClient,
        authStateManager: AuthStateManager(
          deviceIdentityService: _NoopDeviceIdentityService(),
        ),
        profileRepository: _NullProfileRepository(),
        eventBus: eventBus,
      );

      // First fetch: server returns total=5 (one ranked attempt).
      final List<LeaderboardRow> first = await repo.fetchLeaderboard(
        period: LeaderboardPeriod.allTime,
      );
      expect(hitCount, 1);
      expect(first.single.score, 5);

      // Second call within TTL → cached, no extra hit.
      await repo.fetchLeaderboard(period: LeaderboardPeriod.allTime);
      expect(hitCount, 1, reason: 'cache should serve within TTL');

      // Simulate "user just finished a ranked attempt on a different quiz"
      // server now totals 5 + 4 = 9.
      totalScoreToReturn = 9;
      eventBus.emit(const AttemptSubmittedEvent(
        quizId: 'quiz-b',
        mode: 'ranked',
        origin: 'open_access',
        score: 4,
        totalQuestions: 5,
      ));

      // Give the broadcast listener a microtask to run.
      await Future<void>.delayed(Duration.zero);

      final List<LeaderboardRow> third = await repo.fetchLeaderboard(
        period: LeaderboardPeriod.allTime,
      );
      expect(hitCount, 2,
          reason: 'AttemptSubmittedEvent must invalidate the snapshot cache');
      expect(third.single.score, 9,
          reason: 'a ranked attempt on a different quiz must grow the total');

      repo.dispose();
    });
  });
}

class _NoopDeviceIdentityService implements DeviceIdentityService {
  @override
  Future<IdentitySpine> getIdentitySpine() async => const IdentitySpine(
        deviceInstallId: '',
        participantId: '',
        hasBoundProfile: false,
      );

  @override
  Future<void> setBoundProfile(bool value) async {}

  @override
  Future<void> clearIdentity({required bool keepDeviceId}) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NullProfileRepository implements ProfileRepository {
  @override
  Future<UserProfile?> getProfile() async => null;

  @override
  Future<UserProfile?> addRankedPoints(int delta) async => null;

  @override
  Future<void> clearAll() async {}

  @override
  String generateNickname({String? fullName}) => 'Guest';

  @override
  Future<UserProfile> quickJoin({
    required String fullName,
    required String facility,
    required String specialty,
    String? nickname,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile({
    required String nickname,
    required String facility,
    required String specialty,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> mintGuestProfile({int? seedSuffix}) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> restoreFromSnapshot(IdentitySnapshot snapshot) {
    throw UnimplementedError();
  }
}
