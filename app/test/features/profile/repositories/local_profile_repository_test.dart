import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medrash_app/core/infra/auth_state_manager.dart';
import 'package:medrash_app/core/infra/device_identity_service.dart';
import 'package:medrash_app/core/infra/identity_snapshot.dart';
import 'package:medrash_app/core/infra/identity_spine.dart';
import 'package:medrash_app/core/infra/medrash_http_client.dart';
import 'package:medrash_app/features/profile/models/user_profile.dart';
import 'package:medrash_app/features/profile/repositories/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('LocalProfileRepository.mintGuestProfile', () {
    test('persists a Guest-XXXX nickname round-trippable via getProfile', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LocalProfileRepository repo = LocalProfileRepository(prefs);

      final UserProfile minted = await repo.mintGuestProfile(seedSuffix: 4242);
      expect(minted.nickname, 'Guest-4242');
      expect(minted.fullName, 'Guest-4242');
      expect(minted.specialty, 'Doctor');
      expect(minted.facility, '');

      final UserProfile? loaded = await repo.getProfile();
      expect(loaded, isNotNull);
      expect(loaded!.nickname, 'Guest-4242');
    });

    test('omitting seedSuffix yields a nickname matching isGuestNickname', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LocalProfileRepository repo = LocalProfileRepository(prefs);

      final UserProfile minted = await repo.mintGuestProfile();
      expect(ProfileRepository.isGuestNickname(minted.nickname), isTrue);
    });
  });

  group('ProfileRepository.isGuestNickname', () {
    test('matches the canonical guest pattern', () {
      expect(ProfileRepository.isGuestNickname('Guest-1234'), isTrue);
      expect(ProfileRepository.isGuestNickname('Guest-999'), isTrue);
      expect(ProfileRepository.isGuestNickname('  Guest-1234  '), isTrue);
    });

    test('rejects custom nicknames and near-misses', () {
      expect(ProfileRepository.isGuestNickname('Alice'), isFalse);
      expect(ProfileRepository.isGuestNickname('Guest'), isFalse);
      expect(ProfileRepository.isGuestNickname('Guest-12'), isFalse);
      expect(ProfileRepository.isGuestNickname('Guest-12345'), isFalse);
      expect(ProfileRepository.isGuestNickname('guest-1234'), isFalse);
      expect(ProfileRepository.isGuestNickname('SwiftDoctor123'), isFalse);
    });
  });

  group('LocalProfileRepository.quickJoin email', () {
    test('persists normalised email locally and forwards it in profile-sync',
        () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      Map<String, dynamic>? captured;
      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('profile-sync')) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(<String, Object?>{'ok': true}), 200,
              headers: <String, String>{'content-type': 'application/json'});
        }
        return http.Response('{}', 404);
      });
      final MedRashHttpClient httpClient = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mockHttp,
      );
      final AuthStateManager auth = AuthStateManager(
        deviceIdentityService: _FixedDeviceIdentityService(
          deviceInstallId: 'device-1',
          participantId: 'participant-1',
        ),
      );
      await auth.initialize();
      final LocalProfileRepository repo = LocalProfileRepository(
        prefs,
        httpClient: httpClient,
        authStateManager: auth,
      );

      final UserProfile saved = await repo.quickJoin(
        fullName: 'Ada Lovelace',
        facility: 'Korle-Bu',
        specialty: 'Doctor',
        email: '  Ada@Example.COM  ',
      );

      expect(saved.email, 'ada@example.com');
      final UserProfile? reloaded = await repo.getProfile();
      expect(reloaded?.email, 'ada@example.com');
      expect(captured, isNotNull);
      final Map<String, dynamic> profile =
          captured!['profile'] as Map<String, dynamic>;
      expect(profile['email'], 'ada@example.com');
    });

    test('omits email from profile-sync body when blank', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      Map<String, dynamic>? captured;
      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('profile-sync')) {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(<String, Object?>{'ok': true}), 200,
              headers: <String, String>{'content-type': 'application/json'});
        }
        return http.Response('{}', 404);
      });
      final MedRashHttpClient httpClient = MedRashHttpClient(
        functionsBaseUrl: 'https://example.test/.netlify/functions/',
        httpClient: mockHttp,
      );
      final AuthStateManager auth = AuthStateManager(
        deviceIdentityService: _FixedDeviceIdentityService(
          deviceInstallId: 'device-2',
          participantId: 'participant-2',
        ),
      );
      await auth.initialize();
      final LocalProfileRepository repo = LocalProfileRepository(
        prefs,
        httpClient: httpClient,
        authStateManager: auth,
      );

      final UserProfile saved = await repo.quickJoin(
        fullName: 'Bola',
        facility: 'Kumasi',
        specialty: 'Pharmacist',
      );

      // Best-effort sync: poll briefly for the background request to land.
      for (int i = 0; i < 20 && captured == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(saved.email, isNull);
      expect(captured, isNotNull);
      final Map<String, dynamic> profile =
          captured!['profile'] as Map<String, dynamic>;
      expect(profile.containsKey('email'), isFalse);
    });

    test('surfaces EMAIL_TAKEN as EmailTakenException with server message',
        () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final http.Client mockHttp = MockClient((http.Request request) async {
        if (request.url.path.endsWith('profile-sync')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'ok': false,
              'code': 'EMAIL_TAKEN',
              'message': 'That email is already linked to another profile.',
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
          deviceInstallId: 'device-3',
          participantId: 'participant-3',
        ),
      );
      await auth.initialize();
      final LocalProfileRepository repo = LocalProfileRepository(
        prefs,
        httpClient: httpClient,
        authStateManager: auth,
      );

      await expectLater(
        () => repo.quickJoin(
          fullName: 'Chi',
          facility: 'Accra',
          specialty: 'Nurse',
          email: 'chi@example.com',
        ),
        throwsA(
          isA<EmailTakenException>().having(
            (EmailTakenException e) => e.message,
            'message',
            contains('already linked'),
          ),
        ),
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
