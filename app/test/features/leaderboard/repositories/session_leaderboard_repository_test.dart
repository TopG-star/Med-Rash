import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medrash_app/core/infra/auth_state_manager.dart';
import 'package:medrash_app/core/infra/device_identity_service.dart';
import 'package:medrash_app/core/infra/identity_snapshot.dart';
import 'package:medrash_app/core/infra/identity_spine.dart';
import 'package:medrash_app/core/infra/medrash_http_client.dart';
import 'package:medrash_app/features/leaderboard/models/session_leaderboard_row.dart';
import 'package:medrash_app/features/leaderboard/repositories/netlify_supabase_leaderboard_repository.dart';
import 'package:medrash_app/features/profile/models/user_profile.dart';
import 'package:medrash_app/features/profile/repositories/profile_repository.dart';

/// Pins the participant-side contract for `session-leaderboard`:
///   * Identity payload is always sent (server gates membership on it).
///   * Live response is parsed into a [SessionLeaderboardResult] with the
///     requesting user's row flagged `isCurrentUser`.
///   * A 403 NOT_SESSION_PARTICIPANT surfaces as `notAParticipant=true`
///     (UI shows the play-first prompt instead of an empty list).
///   * Missing identity short-circuits and returns the play-first shape
///     without touching the network.
void main() {
  group('NetlifySupabaseLeaderboardRepository.fetchSessionLeaderboard', () {
    test('posts identity payload and parses live result with current-user highlight',
        () async {
      late http.Request capturedRequest;
      final http.Client mockHttp = MockClient((http.Request request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'sessionId': 'sess-1',
            'isLive': true,
            'endsAt': '2030-01-01T00:00:00Z',
            'closedAt': null,
            'requestingUserId': 'user-self',
            'limit': 50,
            'top': <Map<String, Object?>>[
              <String, Object?>{
                'rank': 1,
                'userId': 'user-other',
                'nickname': 'Other',
                'sessionScore': 10,
                'timeTakenMs': 12000,
                'completedAt': '2030-01-01T00:00:00Z',
              },
              <String, Object?>{
                'rank': 2,
                'userId': 'user-self',
                'nickname': 'Me',
                'sessionScore': 8,
                'timeTakenMs': 15000,
                'completedAt': '2030-01-01T00:00:10Z',
              },
            ],
            'me': <String, Object?>{
              'rank': 2,
              'userId': 'user-self',
              'nickname': 'Me',
              'sessionScore': 8,
              'timeTakenMs': 15000,
              'completedAt': '2030-01-01T00:00:10Z',
            },
            'generatedAt': '2030-01-01T00:00:11Z',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final NetlifySupabaseLeaderboardRepository repo = await _buildRepo(
        mockHttp,
        deviceId: 'dev-1',
        participantId: 'part-1',
      );

      final SessionLeaderboardResult result = await repo.fetchSessionLeaderboard(
        sessionId: 'sess-1',
      );

      expect(capturedRequest.url.toString().endsWith('/session-leaderboard'), true);
      final Map<String, dynamic> body =
          jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['sessionId'], 'sess-1');
      expect(body['limit'], 50);
      expect(body['participantId'], 'part-1');
      expect(body['deviceInstallId'], 'dev-1');
      expect(body.containsKey('profile'), true);

      expect(result.isLive, true);
      expect(result.notAParticipant, false);
      expect(result.requestingUserId, 'user-self');
      expect(result.rows, hasLength(2));
      expect(result.rows[0].isCurrentUser, false);
      expect(result.rows[1].isCurrentUser, true,
          reason: 'matching userId must be flagged as current user');
      expect(result.me, isNotNull);
      expect(result.me!.isCurrentUser, true);

      repo.dispose();
    });

    test('surfaces 403 NOT_SESSION_PARTICIPANT as notAParticipant=true',
        () async {
      final http.Client mockHttp = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': false,
            'code': 'NOT_SESSION_PARTICIPANT',
            'message': 'Play first.',
            'isLive': true,
            'endsAt': null,
            'closedAt': null,
          }),
          403,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final NetlifySupabaseLeaderboardRepository repo = await _buildRepo(
        mockHttp,
        deviceId: 'dev-1',
        participantId: 'part-1',
      );

      final SessionLeaderboardResult result = await repo.fetchSessionLeaderboard(
        sessionId: 'sess-1',
      );

      expect(result.notAParticipant, true);
      expect(result.rows, isEmpty);
      expect(result.isLive, true);

      repo.dispose();
    });

    test('returns notAParticipant=true without network when identity missing',
        () async {
      int hitCount = 0;
      final http.Client mockHttp = MockClient((http.Request request) async {
        hitCount += 1;
        return http.Response('{}', 200);
      });

      final NetlifySupabaseLeaderboardRepository repo = await _buildRepo(
        mockHttp,
        deviceId: '',
        participantId: '',
      );

      final SessionLeaderboardResult result = await repo.fetchSessionLeaderboard(
        sessionId: 'sess-1',
      );

      expect(hitCount, 0,
          reason: 'no identity ⇒ must short-circuit before any HTTP call');
      expect(result.notAParticipant, true);
      expect(result.requestingUserId, isNull);

      repo.dispose();
    });
  });
}

Future<NetlifySupabaseLeaderboardRepository> _buildRepo(
  http.Client mockHttp, {
  required String deviceId,
  required String participantId,
}) async {
  final MedRashHttpClient httpClient = MedRashHttpClient(
    functionsBaseUrl: 'https://example.test/.netlify/functions/',
    httpClient: mockHttp,
  );

  final AuthStateManager authState = AuthStateManager(
    deviceIdentityService: _FakeDeviceIdentityService(
      deviceId: deviceId,
      participantId: participantId,
    ),
  );
  await authState.initialize();

  return NetlifySupabaseLeaderboardRepository(
    httpClient: httpClient,
    authStateManager: authState,
    profileRepository: _NullProfileRepository(),
  );
}

class _FakeDeviceIdentityService implements DeviceIdentityService {
  _FakeDeviceIdentityService({
    required this.deviceId,
    required this.participantId,
  });

  final String deviceId;
  final String participantId;

  @override
  Future<IdentitySpine> getIdentitySpine() async => IdentitySpine(
        deviceInstallId: deviceId,
        participantId: participantId,
        hasBoundProfile: false,
      );

  @override
  Future<void> setBoundProfile(bool value) async {}

  @override
  Future<void> clearIdentity({required bool keepDeviceId}) async {}

  @override
  Future<IdentitySnapshot?> readSnapshot() async => null;

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
    String? email,
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

  @override
  Future<UserProfile> persistRecoveredProfile(UserProfile profile) {
    throw UnimplementedError();
  }
}
