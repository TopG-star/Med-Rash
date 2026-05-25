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
import 'package:medrash_app/features/quiz/repositories/quiz_repository.dart';
import 'package:medrash_app/features/quiz/storage/quiz_attempt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression for the "stale Pending Sync banner" bug.
///
/// Scenario: user finishes Quiz A in Session 1 with a failed sync (cached
/// snapshot persists with syncStatus='failed'). They then start a fresh
/// attempt for Quiz B in Session 2 but bail mid-quiz, or navigate to /result
/// some other way. The old Quiz A snapshot used to keep showing its
/// "Pending Sync" banner — even though it belongs to a completely different
/// context the user is no longer in.
///
/// Fix: startAttempt drops the cached completed snapshot when the new
/// attempt's (quizId, sessionId) doesn't match the cached one's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetlifySupabaseQuizRepository.startAttempt cached-snapshot scoping', () {
    test('clears stale cached snapshot when starting an attempt for a different quiz',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'medrash.attempt.completed.v1': jsonEncode(<String, Object?>{
          'quizId': 'old-quiz',
          'modeName': 'ranked',
          'originName': 'qrSession',
          'sessionId': 'session-old',
          'score': 3,
          'totalQuestions': 5,
          'timeTakenMs': 9000,
          'completedAtMs': DateTime.now().millisecondsSinceEpoch,
          'review': <Map<String, Object?>>[],
          'isOfflinePractice': false,
          'syncStatus': 'failed',
          'syncError': 'HTTP 500',
        }),
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final QuizAttemptStore store = QuizAttemptStore(prefs);

      // Mock just enough HTTP for ensureLiveDataReady + ranked-eligibility.
      // Eligibility returns true so startAttempt proceeds; attempt-submit is
      // never hit because we only call startAttempt, not finishAttempt.
      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('quiz-list')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'quizzes': <Map<String, Object?>>[
                <String, Object?>{
                  'slug': 'new-quiz',
                  'title': 'New Quiz',
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
        if (request.url.path.endsWith('ranked-eligibility')) {
          return http.Response(
            jsonEncode(<String, Object?>{'ok': true, 'eligible': true}),
            200,
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
      // Drain the unawaited auto-retry initialize() schedules so it can't
      // race our startAttempt call and re-save the snapshot afterwards.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Sanity: the stale snapshot loaded.
      expect(repo.cachedCompletedNeedsSync, isTrue,
          reason: 'precondition: stale failed snapshot must be present');
      expect(repo.getCachedCompletedAttempt(), isNotNull);

      // Now start an attempt for a DIFFERENT quiz — must drop the stale one.
      await repo.startAttempt(
        quizId: 'new-quiz',
        mode: QuizMode.ranked,
        origin: AttemptOrigin.qrSession,
        sessionId: 'session-new',
      );

      expect(repo.cachedCompletedNeedsSync, isFalse,
          reason: 'starting a different-quiz attempt must drop the stale snapshot');
      expect(repo.getCachedCompletedAttempt(), isNull);
      expect(store.loadCompleted(), isNull,
          reason: 'stale snapshot must also be wiped from persistent storage');
    });

    test('preserves cached snapshot when re-starting the same (quizId, sessionId)',
        () async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        'medrash.attempt.completed.v1': jsonEncode(<String, Object?>{
          'quizId': 'same-quiz',
          'modeName': 'learning',
          'originName': 'openAccess',
          'sessionId': null,
          'score': 4,
          'totalQuestions': 5,
          'timeTakenMs': 8000,
          'completedAtMs': now,
          'review': <Map<String, Object?>>[],
          'isOfflinePractice': false,
          'syncStatus': 'failed',
          'syncError': 'HTTP 500',
        }),
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final QuizAttemptStore store = QuizAttemptStore(prefs);

      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('quiz-list')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'quizzes': <Map<String, Object?>>[
                <String, Object?>{
                  'slug': 'same-quiz',
                  'title': 'Same Quiz',
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
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Learning mode, same quiz, no session — re-starting must preserve so
      // the user can still see + retry their unsynced result.
      await repo.startAttempt(
        quizId: 'same-quiz',
        mode: QuizMode.learning,
        origin: AttemptOrigin.openAccess,
      );

      expect(repo.getCachedCompletedAttempt(), isNotNull,
          reason: 'same-context startAttempt must NOT drop the snapshot');
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

  @override
  Future<UserProfile> persistRecoveredProfile(UserProfile profile) {
    throw UnimplementedError();
  }
}
