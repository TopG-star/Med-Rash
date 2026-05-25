import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'identity_snapshot.dart';
import 'identity_spine.dart';

class DeviceIdentityService {
  DeviceIdentityService(this._preferences);

  static const String _deviceKey = 'medrash.device.install_id';
  static const String _participantKey = 'medrash.participant.id';
  static const String _boundProfileKey = 'medrash.device.bound_profile';
  static const String _snapshotKey = 'medrash.identity.last_signed_out';

  final SharedPreferences _preferences;

  Future<String> getOrCreateDeviceId() async {
    final String? existing = _preferences.getString(_deviceKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final Random random = Random();
    final String deviceId = List<String>.generate(
      4,
      (_) => random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0'),
    ).join('-');

    await _preferences.setString(_deviceKey, deviceId);
    return deviceId;
  }

  Future<String> getOrCreateParticipantId() async {
    final String? existing = _preferences.getString(_participantKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final Random random = Random();
    final String randomHex = List<String>.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final String participantId = 'pid-$randomHex';
    await _preferences.setString(_participantKey, participantId);
    return participantId;
  }

  Future<IdentitySpine> getIdentitySpine() async {
    return IdentitySpine(
      deviceInstallId: await getOrCreateDeviceId(),
      participantId: await getOrCreateParticipantId(),
      hasBoundProfile: hasBoundProfile(),
    );
  }

  bool hasBoundProfile() {
    return _preferences.getBool(_boundProfileKey) ?? false;
  }

  Future<void> setBoundProfile(bool value) async {
    await _preferences.setBool(_boundProfileKey, value);
  }

  /// Wipes the participant binding so the next [getIdentitySpine] mints a
  /// fresh participant id (and, when [keepDeviceId] is false, a fresh device
  /// install id too).
  ///
  /// Two intended call sites:
  /// - "Sign out on this device" → keepDeviceId=true. Same device, new
  ///   participant. Used when the same human wants a clean slate.
  /// - "Hand to someone else" → keepDeviceId=false. New device, new
  ///   participant. Used when a phone is passed to a different participant
  ///   so the leaderboard treats them as a separate row.
  Future<void> clearIdentity({required bool keepDeviceId}) async {
    await _preferences.remove(_participantKey);
    await _preferences.remove(_boundProfileKey);
    if (!keepDeviceId) {
      await _preferences.remove(_deviceKey);
    }
  }

  /// Restores the participant + device install ids to the values captured at
  /// soft sign-out so the server's `identity_spine_id` lookup resolves back
  /// to the original user row.
  Future<void> restoreIdentity(IdentitySnapshot snapshot) async {
    await _preferences.setString(_deviceKey, snapshot.deviceInstallId);
    await _preferences.setString(_participantKey, snapshot.participantId);
    await _preferences.setBool(_boundProfileKey, true);
  }

  /// Adopts a participant id recovered from the server (slice 6b OTP flow)
  /// in place of the freshly-minted guest id on this install. The device
  /// install id is preserved on disk because the server already merged the
  /// guest user_id into the recovered user_id, so any downstream call keyed
  /// on this device must now resolve to the recovered participant.
  Future<void> adoptRecoveredIdentity({
    required String participantId,
    required String deviceInstallId,
  }) async {
    await _preferences.setString(_deviceKey, deviceInstallId);
    await _preferences.setString(_participantKey, participantId);
    await _preferences.setBool(_boundProfileKey, true);
  }

  /// Returns the last soft-sign-out snapshot, or null if absent or expired.
  /// Expired snapshots are eagerly deleted so a stale device never resurrects
  /// a stranger's identity.
  Future<IdentitySnapshot?> readSnapshot() async {
    final IdentitySnapshot? snapshot =
        IdentitySnapshot.tryDecode(_preferences.getString(_snapshotKey));
    if (snapshot == null) {
      return null;
    }
    if (snapshot.isExpired) {
      await _preferences.remove(_snapshotKey);
      return null;
    }
    return snapshot;
  }

  Future<void> writeSnapshot(IdentitySnapshot snapshot) async {
    await _preferences.setString(_snapshotKey, snapshot.encode());
  }

  Future<void> clearSnapshot() async {
    await _preferences.remove(_snapshotKey);
  }
}
