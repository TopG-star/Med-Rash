import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'identity_spine.dart';

class DeviceIdentityService {
  DeviceIdentityService(this._preferences);

  static const String _deviceKey = 'medrash.device.install_id';
  static const String _participantKey = 'medrash.participant.id';
  static const String _boundProfileKey = 'medrash.device.bound_profile';

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
}
