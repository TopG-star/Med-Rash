import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medrash_app/core/infra/auth_state_manager.dart';
import 'package:medrash_app/core/infra/device_identity_service.dart';
import 'package:medrash_app/core/infra/event_bus.dart';
import 'package:medrash_app/core/infra/identity_snapshot.dart';
import 'package:medrash_app/core/infra/identity_spine.dart';
import 'package:medrash_app/core/infra/medrash_http_client.dart';
import 'package:medrash_app/features/profile/models/user_profile.dart';
import 'package:medrash_app/features/profile/repositories/profile_repository.dart';
import 'package:medrash_app/features/quiz/repositories/netlify_supabase_quiz_repository.dart';
import 'package:medrash_app/features/quiz/storage/quiz_attempt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression for the "stuck Pending Sync" bug.
///
/// `finishAttempt` already maps a 409 `RANKED_ATTEMPT_ALREADY_EXISTS` to
/// `syncStatus='synced'` (the server has the row; the response was just lost).
/// The retry path used to mark it `'failed'` and rethrow, leaving the result
/// page stuck on the "Pending Sync" banner forever. This test pins the
/// symmetry: a 409 on retry must clear the banner too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetlifySupabaseQuizRepository.retrySyncCachedAttempt', () {
    test('409 RANKED_ATTEMPT_ALREADY_EXISTS on retry flips snapshot to synced',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'medrash.attempt.completed.v1': jsonEncode(<String, Object?>{
          'quizId': 'neonatal-resus',
          'modeName': 'ranked',
          'originName': 'qrSession',
          'sessionId': 'session-uuid-1',
          'score': 4,
          'totalQuestions': 5,
          'timeTakenMs': 12345,
          'completedAtMs': DateTime.now().millisecondsSinceEpoch,
          'review': <Map<String, Object?>>[],
          'isOfflinePractice': false,
          'syncStatus': 'failed',
          'syncError': 'HTTP 500',
        }),
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final QuizAttemptStore store = QuizAttemptStore(prefs);

      int quizListHits = 0;
      int attemptSubmitHits = 0;

      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('quiz-list')) {
          quizListHits += 1;
          return http.Response(
            jsonEncode(<String, Object?>{
              'quizzes': <Map<String, Object?>>[
                <String, Object?>{
                  'slug': 'neonatal-resus',
                  'title': 'Neonatal Resus',
                  'category': 'OB',
                  'product': 'Clinical',
                  'summary': '',
                  'metadata': <String, Object?>{
                    'difficulty': 'Core',
                    'duration_label': '5 min',
                  },
                  'questions': <Map<String, Object?>>[
                    <String, Object?>{
                      'id': 'q1',
                      'prompt': 'p',
                      'options': <String>['a', 'b'],
                      'correct_index': 0,
                    },
                  ],
                },
              ],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('attempt-submit')) {
          attemptSubmitHits += 1;
          return http.Response(
            jsonEncode(<String, Object?>{
              'ok': false,
              'code': 'RANKED_ATTEMPT_ALREADY_EXISTS',
              'message': 'Ranked attempt already exists for this user and quiz.',
            }),
            409,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      final MedRashHttpClient httpClient = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mockHttp,
      );

      final AuthStateManager auth = AuthStateManager(
        deviceIdentityService: _FixedDeviceIdentityService(
          deviceInstallId: 'device-abc',
          participantId: 'participant-xyz',
        ),
      );
      await auth.initialize();

      final NetlifySupabaseQuizRepository repo = NetlifySupabaseQuizRepository(
        httpClient: httpClient,
        authStateManager: auth,
        profileRepository: _StubProfileRepository(),
        store: store,
        eventBus: EventBus(),
      );

      await repo.initialize();
      // initialize() schedules an unawaited auto-retry. Drain it before any
      // explicit retry call so we observe the post-retry state, not a race.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // After the auto-retry, the snapshot must already be 'synced' (banner
      // cleared) — NOT stuck at 'failed'.
      expect(quizListHits, greaterThanOrEqualTo(1));
      expect(attemptSubmitHits, greaterThanOrEqualTo(1));
      expect(repo.cachedCompletedNeedsSync, isFalse,
          reason:
              '409 on retry must clear the Pending Sync banner the same way finishAttempt does.');

      final PersistedCompletedAttempt? finalSnapshot = store.loadCompleted();
      expect(finalSnapshot, isNotNull);
      expect(finalSnapshot!.syncStatus, 'synced');
      expect(finalSnapshot.syncError, isNull);
    });
  });
}

class _FixedDeviceIdentityService implements DeviceIdentityService {
  _FixedDeviceIdentityService({
    required this.deviceInstallId,
    required this.participantId,
  });

  final String deviceInstallId;
  final String participantId;
  bool _hasProfile = true;

  @override
  Future<IdentitySpine> getIdentitySpine() async => IdentitySpine(
        deviceInstallId: deviceInstallId,
        participantId: participantId,
        hasBoundProfile: _hasProfile,
      );

  @override
  Future<void> setBoundProfile(bool value) async {
    _hasProfile = value;
  }

  @override
  Future<void> clearIdentity({required bool keepDeviceId}) async {
    _hasProfile = false;
  }

  @override
  Future<void> restoreIdentity(IdentitySnapshot snapshot) async {}

  @override
  Future<IdentitySnapshot?> readSnapshot() async => null;

  @override
  Future<void> writeSnapshot(IdentitySnapshot snapshot) async {}

  @override
  Future<void> clearSnapshot() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubProfileRepository implements ProfileRepository {
  @override
  Future<UserProfile?> getProfile() async => const UserProfile(
        fullName: 'Test User',
        nickname: 'Tester',
        facility: 'Test Facility',
        specialty: 'Doctor',
        totalPoints: 0,
        rank: 0,
      );

  @override
  Future<UserProfile?> addRankedPoints(int delta) async => null;

  @override
  Future<void> clearAll() async {}

  @override
  String generateNickname({String? fullName}) => 'Tester';

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
}
