import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

abstract class ProfileRepository {
  Future<UserProfile?> getProfile();

  Future<UserProfile> quickJoin({
    required String fullName,
    required String facility,
    required String specialty,
    String? nickname,
  });

  Future<UserProfile> updateProfile({
    required String nickname,
    required String facility,
    required String specialty,
  });

  String generateNickname({String? fullName});
}

class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository(this._preferences);

  final SharedPreferences _preferences;

  static const String _keyFullName = 'medrash.profile.full_name';
  static const String _keyNickname = 'medrash.profile.nickname';
  static const String _keyFacility = 'medrash.profile.facility';
  static const String _keySpecialty = 'medrash.profile.specialty';
  static const String _keyTotalPoints = 'medrash.profile.total_points';
  static const String _keyRank = 'medrash.profile.rank';

  @override
  Future<UserProfile?> getProfile() async {
    final String? fullName = _preferences.getString(_keyFullName);
    if (fullName == null || fullName.isEmpty) {
      return null;
    }

    return UserProfile(
      fullName: fullName,
      nickname: _preferences.getString(_keyNickname) ?? generateNickname(fullName: fullName),
      facility: _preferences.getString(_keyFacility) ?? '',
      specialty: _preferences.getString(_keySpecialty) ?? 'Doctor',
      totalPoints: _preferences.getInt(_keyTotalPoints) ?? 0,
      rank: _preferences.getInt(_keyRank) ?? 0,
    );
  }

  @override
  Future<UserProfile> quickJoin({
    required String fullName,
    required String facility,
    required String specialty,
    String? nickname,
  }) async {
    final String generatedNickname = nickname?.trim().isNotEmpty == true
        ? nickname!.trim()
        : generateNickname(fullName: fullName);

    const int seedPoints = 0;
    const int seedRank = 0;

    await _preferences.setString(_keyFullName, fullName.trim());
    await _preferences.setString(_keyFacility, facility.trim());
    await _preferences.setString(_keySpecialty, specialty.trim());
    await _preferences.setString(_keyNickname, generatedNickname);
    await _preferences.setInt(_keyTotalPoints, seedPoints);
    await _preferences.setInt(_keyRank, seedRank);

    return UserProfile(
      fullName: fullName.trim(),
      nickname: generatedNickname,
      facility: facility.trim(),
      specialty: specialty.trim(),
      totalPoints: seedPoints,
      rank: seedRank,
    );
  }

  @override
  Future<UserProfile> updateProfile({
    required String nickname,
    required String facility,
    required String specialty,
  }) async {
    final UserProfile? existing = await getProfile();
    if (existing == null) {
      throw StateError('Cannot update profile before quick join.');
    }

    await _preferences.setString(_keyNickname, nickname.trim());
    await _preferences.setString(_keyFacility, facility.trim());
    await _preferences.setString(_keySpecialty, specialty.trim());

    return UserProfile(
      fullName: existing.fullName,
      nickname: nickname.trim(),
      facility: facility.trim(),
      specialty: specialty.trim(),
      totalPoints: existing.totalPoints,
      rank: existing.rank,
    );
  }

  @override
  String generateNickname({String? fullName}) {
    final Random random = Random();
    final int suffix = random.nextInt(900) + 100;
    final String seed = fullName?.trim() ?? '';
    if (seed.isEmpty) {
      return 'SwiftDoctor$suffix';
    }

    final List<String> parts = seed.split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    final String primary = parts.isNotEmpty ? parts.first : 'Medic';
    final String compact = primary.replaceAll(RegExp(r'[^A-Za-z]'), '');
    final String normalized = compact.isEmpty ? 'Medic' : compact;
    final String stem = normalized.length <= 10 ? normalized : normalized.substring(0, 10);
    return '$stem$suffix';
  }
}
