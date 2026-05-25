import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medrash_app/core/infra/auth_state_manager.dart';
import 'package:medrash_app/core/infra/device_identity_service.dart';
import 'package:medrash_app/core/infra/identity_snapshot.dart';
import 'package:medrash_app/core/infra/identity_spine.dart';
import 'package:medrash_app/core/infra/medrash_http_client.dart';
import 'package:medrash_app/features/profile/repositories/recovery_repository.dart';

const String _functionsBase = 'https://example.test/.netlify/functions/';

Future<AuthStateManager> _buildAuth({
  String deviceId = 'device-1',
  String participantId = 'participant-1',
}) async {
  final AuthStateManager auth = AuthStateManager(
    deviceIdentityService: _FixedDeviceIdentityService(
      deviceInstallId: deviceId,
      participantId: participantId,
    ),
  );
  await auth.initialize();
  return auth;
}

NetlifyRecoveryRepository _buildRepo({
  required http.Client mockHttp,
  required AuthStateManager auth,
}) {
  final MedRashHttpClient httpClient = MedRashHttpClient(
    functionsBaseUrl: _functionsBase,
    httpClient: mockHttp,
  );
  return NetlifyRecoveryRepository(
    httpClient: httpClient,
    authStateManager: auth,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetlifyRecoveryRepository.requestOtp', () {
    test('posts a normalised email and returns void on 200 ok', () async {
      Map<String, dynamic>? captured;
      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('recover-request')) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200,
              headers: <String, String>{'content-type': 'application/json'});
        }
        return http.Response('{}', 404);
      });
      final AuthStateManager auth = await _buildAuth();
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      await repo.requestOtp(email: '  Ada@Example.org  ');

      expect(captured, isNotNull);
      expect(captured!['email'], 'ada@example.org');
    });

    test('throws ProfileNotFoundException on 404 PROFILE_NOT_FOUND', () async {
      final http.Client mockHttp = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': false,
            'code': 'PROFILE_NOT_FOUND',
            'message': 'No profile found for that email.',
          }),
          404,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final AuthStateManager auth = await _buildAuth();
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      await expectLater(
        repo.requestOtp(email: 'ghost@example.org'),
        throwsA(isA<ProfileNotFoundException>()),
      );
    });

    test('throws RecoveryRateLimitedException on 429 RATE_LIMITED', () async {
      final http.Client mockHttp = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': false,
            'code': 'RATE_LIMITED',
            'message': 'Too many requests.',
          }),
          429,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final AuthStateManager auth = await _buildAuth();
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      await expectLater(
        repo.requestOtp(email: 'a@b.test'),
        throwsA(isA<RecoveryRateLimitedException>()),
      );
    });

    test('throws OtpDeliveryFailedException on 502 OTP_SEND_FAILED', () async {
      final http.Client mockHttp = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': false,
            'code': 'OTP_SEND_FAILED',
            'message': 'Mail server down.',
          }),
          502,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final AuthStateManager auth = await _buildAuth();
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      await expectLater(
        repo.requestOtp(email: 'a@b.test'),
        throwsA(isA<OtpDeliveryFailedException>()),
      );
    });

    test('rejects empty email without a network call', () async {
      bool called = false;
      final http.Client mockHttp = MockClient((http.Request request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final AuthStateManager auth = await _buildAuth();
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      await expectLater(
        repo.requestOtp(email: '   '),
        throwsA(isA<RecoveryNetworkException>()),
      );
      expect(called, isFalse);
    });
  });

  group('NetlifyRecoveryRepository.verifyOtp', () {
    test('posts email + otp + deviceInstallId + currentParticipantId and parses the recovered identity',
        () async {
      Map<String, dynamic>? captured;
      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('recover-verify')) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'ok': true,
              'participantId': 'pid-recovered',
              'deviceInstallId': 'device-1',
              'profile': <String, Object?>{
                'fullName': 'Ada Lovelace',
                'nickname': 'ada',
                'facility': 'Analytical Engine Lab',
                'specialty': 'Computer Science',
                'email': 'ada@example.org',
              },
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });
      final AuthStateManager auth = await _buildAuth(
        deviceId: 'device-1',
        participantId: 'guest-pid',
      );
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      final RecoveredIdentity recovered = await repo.verifyOtp(
        email: 'ada@example.org',
        otp: '123456',
      );

      expect(captured, isNotNull);
      expect(captured!['email'], 'ada@example.org');
      expect(captured!['otp'], '123456');
      expect(captured!['deviceInstallId'], 'device-1');
      expect(captured!['currentParticipantId'], 'guest-pid');

      expect(recovered.participantId, 'pid-recovered');
      expect(recovered.deviceInstallId, 'device-1');
      expect(recovered.profile.fullName, 'Ada Lovelace');
      expect(recovered.profile.nickname, 'ada');
      expect(recovered.profile.facility, 'Analytical Engine Lab');
      expect(recovered.profile.specialty, 'Computer Science');
      expect(recovered.profile.email, 'ada@example.org');
      // Points/rank are server-truth: repo zeros them locally and lets the
      // next leaderboard fetch fill the real numbers in.
      expect(recovered.profile.totalPoints, 0);
      expect(recovered.profile.rank, 0);
    });

    test('throws OtpInvalidException on 400 OTP_INVALID', () async {
      final http.Client mockHttp = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': false,
            'code': 'OTP_INVALID',
            'message': 'That code did not match.',
          }),
          400,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final AuthStateManager auth = await _buildAuth();
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      await expectLater(
        repo.verifyOtp(email: 'a@b.test', otp: '000000'),
        throwsA(isA<OtpInvalidException>()),
      );
    });

    test('throws RecoveryConflictException on 409 RECOVERY_CONFLICT', () async {
      final http.Client mockHttp = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': false,
            'code': 'RECOVERY_CONFLICT',
            'message': 'Email is bound to a different auth identity.',
          }),
          409,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final AuthStateManager auth = await _buildAuth();
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      await expectLater(
        repo.verifyOtp(email: 'a@b.test', otp: '123456'),
        throwsA(isA<RecoveryConflictException>()),
      );
    });

    test('throws RecoveryNetworkException when payload is incomplete', () async {
      final http.Client mockHttp = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{'ok': true}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final AuthStateManager auth = await _buildAuth();
      final NetlifyRecoveryRepository repo =
          _buildRepo(mockHttp: mockHttp, auth: auth);

      await expectLater(
        repo.verifyOtp(email: 'a@b.test', otp: '123456'),
        throwsA(isA<RecoveryNetworkException>()),
      );
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
