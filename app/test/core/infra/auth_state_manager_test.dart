import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/infra/auth_state_manager.dart';
import 'package:medrash_app/core/infra/device_identity_service.dart';
import 'package:medrash_app/core/infra/identity_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _snapshotKey = 'medrash.identity.last_signed_out';
const String _deviceKey = 'medrash.device.install_id';
const String _participantKey = 'medrash.participant.id';
const String _boundProfileKey = 'medrash.device.bound_profile';

const ProfileSnapshotInput _profile = ProfileSnapshotInput(
  fullName: 'Ada Lovelace',
  nickname: 'ada',
  facility: 'St. Mary',
  specialty: 'Cardiology',
  totalPoints: 420,
  rank: 7,
);

Future<AuthStateManager> _bootAuth({
  Map<String, Object> seed = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(seed);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final DeviceIdentityService device = DeviceIdentityService(prefs);
  final AuthStateManager auth = AuthStateManager(deviceIdentityService: device);
  await auth.initialize();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthStateManager soft sign-out (keepDeviceId: true)', () {
    test('with profile writes a snapshot and exposes it on the manager',
        () async {
      final AuthStateManager auth = await _bootAuth();
      final String? originalParticipant = auth.participantId;
      final String? originalDevice = auth.deviceId;
      expect(originalParticipant, isNotNull);
      expect(originalDevice, isNotNull);

      await auth.signOut(keepDeviceId: true, profile: _profile);

      final IdentitySnapshot? snapshot = auth.lastSignedOutSnapshot;
      expect(snapshot, isNotNull);
      expect(snapshot!.participantId, originalParticipant);
      expect(snapshot.deviceInstallId, originalDevice);
      expect(snapshot.nickname, 'ada');
      expect(snapshot.totalPoints, 420);

      // Participant rotated even though snapshot survives.
      expect(auth.participantId, isNot(equals(originalParticipant)));
      expect(auth.hasProfile, isFalse);
    });

    test('without profile clears any pre-existing snapshot', () async {
      final IdentitySnapshot existing = IdentitySnapshot(
        participantId: 'pid-old',
        deviceInstallId: 'dev-old',
        fullName: 'Old',
        nickname: 'old',
        facility: '',
        specialty: '',
        totalPoints: 0,
        rank: 0,
        signedOutAt: DateTime.now(),
      );
      final AuthStateManager auth = await _bootAuth(
        seed: <String, Object>{_snapshotKey: existing.encode()},
      );
      expect(auth.lastSignedOutSnapshot, isNotNull);

      await auth.signOut(keepDeviceId: true);

      expect(auth.lastSignedOutSnapshot, isNull);
    });
  });

  group('AuthStateManager hard sign-out (keepDeviceId: false)', () {
    test('always clears the snapshot even when a profile is passed', () async {
      final AuthStateManager auth = await _bootAuth();
      await auth.signOut(keepDeviceId: false, profile: _profile);

      expect(auth.lastSignedOutSnapshot, isNull);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_snapshotKey), isNull);
    });
  });

  group('AuthStateManager.restoreFromSnapshot', () {
    test('rehydrates spine to the snapshot ids and drops the snapshot',
        () async {
      final AuthStateManager auth = await _bootAuth();
      await auth.signOut(keepDeviceId: true, profile: _profile);
      final IdentitySnapshot snapshot = auth.lastSignedOutSnapshot!;

      await auth.restoreFromSnapshot(snapshot);

      expect(auth.participantId, snapshot.participantId);
      expect(auth.deviceId, snapshot.deviceInstallId);
      expect(auth.hasProfile, isTrue);
      expect(auth.lastSignedOutSnapshot, isNull);
    });
  });

  group('AuthStateManager.dismissLastSnapshot', () {
    test('clears the snapshot without rotating the live spine', () async {
      final AuthStateManager auth = await _bootAuth();
      await auth.signOut(keepDeviceId: true, profile: _profile);
      final String? participantAfterSignOut = auth.participantId;
      final String? deviceAfterSignOut = auth.deviceId;

      await auth.dismissLastSnapshot();

      expect(auth.lastSignedOutSnapshot, isNull);
      expect(auth.participantId, participantAfterSignOut);
      expect(auth.deviceId, deviceAfterSignOut);
    });
  });

  group('AuthStateManager.initialize', () {
    test('hydrates an existing valid snapshot from disk', () async {
      final IdentitySnapshot stored = IdentitySnapshot(
        participantId: 'pid-stored',
        deviceInstallId: 'dev-stored',
        fullName: 'Stored',
        nickname: 'stored',
        facility: 'Clinic',
        specialty: 'GP',
        totalPoints: 10,
        rank: 1,
        signedOutAt: DateTime.now(),
      );
      final AuthStateManager auth = await _bootAuth(
        seed: <String, Object>{_snapshotKey: stored.encode()},
      );

      expect(auth.lastSignedOutSnapshot, isNotNull);
      expect(auth.lastSignedOutSnapshot!.nickname, 'stored');
    });

    test('treats an expired snapshot as absent and wipes it', () async {
      final DateTime stale =
          DateTime.now().subtract(IdentitySnapshot.maxAge + const Duration(days: 1));
      final Map<String, Object?> payload = <String, Object?>{
        'participantId': 'pid-stale',
        'deviceInstallId': 'dev-stale',
        'fullName': 'Stale',
        'nickname': 'stale',
        'facility': '',
        'specialty': '',
        'totalPoints': 0,
        'rank': 0,
        'signedOutAt': stale.toIso8601String(),
      };
      final AuthStateManager auth = await _bootAuth(
        seed: <String, Object>{_snapshotKey: jsonEncode(payload)},
      );

      expect(auth.lastSignedOutSnapshot, isNull);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_snapshotKey), isNull,
          reason: 'expired snapshot must be removed eagerly');
    });
  });

  group('DeviceIdentityService.restoreIdentity', () {
    test('writes the snapshot ids and marks profile bound', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final DeviceIdentityService device = DeviceIdentityService(prefs);

      final IdentitySnapshot snapshot = IdentitySnapshot(
        participantId: 'pid-restore',
        deviceInstallId: 'dev-restore',
        fullName: 'R',
        nickname: 'r',
        facility: '',
        specialty: '',
        totalPoints: 0,
        rank: 0,
        signedOutAt: DateTime.now(),
      );
      await device.restoreIdentity(snapshot);

      expect(prefs.getString(_deviceKey), 'dev-restore');
      expect(prefs.getString(_participantKey), 'pid-restore');
      expect(prefs.getBool(_boundProfileKey), isTrue);
    });
  });

  group('AuthStateManager.adoptRecoveredIdentity', () {
    test('swaps the participant id, keeps the device, marks profile bound',
        () async {
      final AuthStateManager auth = await _bootAuth();
      final String? originalDevice = auth.deviceId;
      expect(originalDevice, isNotNull);

      await auth.adoptRecoveredIdentity(
        participantId: 'pid-recovered',
        deviceInstallId: originalDevice!,
      );

      expect(auth.participantId, 'pid-recovered');
      expect(auth.deviceId, originalDevice);
      expect(auth.hasProfile, isTrue);
      expect(auth.lastSignedOutSnapshot, isNull);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_participantKey), 'pid-recovered');
      expect(prefs.getString(_deviceKey), originalDevice);
      expect(prefs.getBool(_boundProfileKey), isTrue);
    });

    test('also clears any stale soft-sign-out snapshot', () async {
      final AuthStateManager auth = await _bootAuth();
      await auth.signOut(keepDeviceId: true, profile: _profile);
      expect(auth.lastSignedOutSnapshot, isNotNull);

      await auth.adoptRecoveredIdentity(
        participantId: 'pid-new',
        deviceInstallId: auth.deviceId!,
      );

      expect(auth.lastSignedOutSnapshot, isNull);
    });
  });
}
