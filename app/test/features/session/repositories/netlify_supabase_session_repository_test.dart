import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medrash_app/core/infra/auth_state_manager.dart';
import 'package:medrash_app/core/infra/device_identity_service.dart';
import 'package:medrash_app/core/infra/identity_snapshot.dart';
import 'package:medrash_app/core/infra/identity_spine.dart';
import 'package:medrash_app/core/infra/medrash_http_client.dart';
import 'package:medrash_app/features/session/repositories/netlify_supabase_session_repository.dart';
import 'package:medrash_app/features/session/repositories/session_repository.dart';

/// Regression for the "admin can't see scans" gap.
///
/// `session-resolve` now accepts optional `participantId` + `deviceInstallId`
/// so the server can log a join event and the admin Live view can show
/// "X devices resolved this code". The mobile repo must include identity
/// when AuthStateManager has one — but must NOT break the resolve flow if
/// identity is missing (defensive: scan still wins).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetlifySupabaseSessionRepository.resolveSessionByJoinCode', () {
    test('includes participantId + deviceInstallId when AuthStateManager has identity',
        () async {
      Map<String, dynamic>? capturedBody;

      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('session-resolve')) {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'ok': true,
              'session': <String, Object?>{
                'sessionId': 'session-uuid-1',
                'joinCode': 'ABCDE',
                'quizId': 'neonatal-resus',
                'title': 'Live Session',
                'category': 'CME',
                'topic': 'topic',
                'questionCount': 5,
                'timeLimit': '02m',
                'host': 'Lead',
              },
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

      final SessionRepository repo = NetlifySupabaseSessionRepository(
        httpClient: httpClient,
        authStateManager: auth,
      );

      await repo.resolveSessionByJoinCode('abcde');

      expect(capturedBody, isNotNull);
      expect(capturedBody!['joinCode'], 'abcde');
      expect(capturedBody!['participantId'], 'participant-xyz');
      expect(capturedBody!['deviceInstallId'], 'device-abc');
    });

    test('omits identity gracefully when AuthStateManager is null', () async {
      Map<String, dynamic>? capturedBody;

      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('session-resolve')) {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'ok': true,
              'session': <String, Object?>{
                'sessionId': 'session-uuid-2',
                'joinCode': 'FGHIJ',
                'quizId': 'q',
                'title': 't',
                'category': 'c',
                'topic': 'to',
                'questionCount': 5,
                'timeLimit': '02m',
                'host': 'h',
              },
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

      final SessionRepository repo = NetlifySupabaseSessionRepository(
        httpClient: httpClient,
      );

      await repo.resolveSessionByJoinCode('fghij');

      expect(capturedBody, isNotNull);
      expect(capturedBody!['joinCode'], 'fghij');
      expect(capturedBody!.containsKey('participantId'), isFalse);
      expect(capturedBody!.containsKey('deviceInstallId'), isFalse);
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
