import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/events/medrash_events.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/infra/medrash_http_client.dart';
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

  /// Wipe every `medrash.profile.*` key. Used by sign-out so the next user of
  /// this device starts at the quick-join screen with a blank slate.
  Future<void> clearAll();

  /// Increment the persisted career-points counter by [delta]. Called when a
  /// ranked attempt is successfully submitted so the Profile screen reflects
  /// the cumulative score across every quiz the participant has played.
  Future<UserProfile?> addRankedPoints(int delta);

  String generateNickname({String? fullName});
}

class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository(
    this._preferences, {
    EventBus? eventBus,
    MedRashHttpClient? httpClient,
    AuthStateManager? authStateManager,
  })  : _eventBus = eventBus,
        _httpClient = httpClient,
        _authStateManager = authStateManager {
    // Singleton-scoped subscription: the repo lives for the whole app
    // lifetime so no explicit cancellation is needed.
    eventBus?.on<AttemptSubmittedEvent>().listen(_onAttemptSubmitted);
  }

  final SharedPreferences _preferences;
  final EventBus? _eventBus;
  final MedRashHttpClient? _httpClient;
  final AuthStateManager? _authStateManager;

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

    final UserProfile profile = UserProfile(
      fullName: fullName.trim(),
      nickname: generatedNickname,
      facility: facility.trim(),
      specialty: specialty.trim(),
      totalPoints: seedPoints,
      rank: seedRank,
    );

    _broadcastProfileUpdate(profile);
    return profile;
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

    final UserProfile profile = UserProfile(
      fullName: existing.fullName,
      nickname: nickname.trim(),
      facility: facility.trim(),
      specialty: specialty.trim(),
      totalPoints: existing.totalPoints,
      rank: existing.rank,
    );

    _broadcastProfileUpdate(profile);
    return profile;
  }

  @override
  Future<void> clearAll() async {
    await _preferences.remove(_keyFullName);
    await _preferences.remove(_keyNickname);
    await _preferences.remove(_keyFacility);
    await _preferences.remove(_keySpecialty);
    await _preferences.remove(_keyTotalPoints);
    await _preferences.remove(_keyRank);
  }

  @override
  Future<UserProfile?> addRankedPoints(int delta) async {
    if (delta <= 0) {
      return getProfile();
    }
    final UserProfile? existing = await getProfile();
    if (existing == null) {
      return null;
    }
    final int next = existing.totalPoints + delta;
    await _preferences.setInt(_keyTotalPoints, next);
    return UserProfile(
      fullName: existing.fullName,
      nickname: existing.nickname,
      facility: existing.facility,
      specialty: existing.specialty,
      totalPoints: next,
      rank: existing.rank,
    );
  }

  void _onAttemptSubmitted(AttemptSubmittedEvent event) {
    // Career points only count ranked attempts. Learning/offline runs are
    // free practice and must never inflate the total.
    if (event.mode != 'ranked') return;
    if (event.score <= 0) return;
    unawaited(_applyRankedPoints(event.score));
  }

  Future<void> _applyRankedPoints(int delta) async {
    final UserProfile? updated = await addRankedPoints(delta);
    if (updated == null) return;
    _eventBus?.emit(ProfilePointsUpdatedEvent(totalPoints: updated.totalPoints));
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

  void _broadcastProfileUpdate(UserProfile profile) {
    _eventBus?.emit(ProfileUpdatedEvent(
      fullName: profile.fullName,
      nickname: profile.nickname,
      facility: profile.facility,
      specialty: profile.specialty,
    ));
    unawaited(_syncProfileToServer(profile));
  }

  Future<void> _syncProfileToServer(UserProfile profile) async {
    final MedRashHttpClient? httpClient = _httpClient;
    final AuthStateManager? authStateManager = _authStateManager;
    if (httpClient == null || authStateManager == null) {
      return;
    }

    final String? participantId = authStateManager.participantId;
    final String? deviceInstallId = authStateManager.deviceId;
    if (participantId == null ||
        participantId.isEmpty ||
        deviceInstallId == null ||
        deviceInstallId.isEmpty) {
      return;
    }

    try {
      await httpClient.postJson('profile-sync', <String, Object?>{
        'participantId': participantId,
        'deviceInstallId': deviceInstallId,
        'profile': <String, Object?>{
          'fullName': profile.fullName,
          'nickname': profile.nickname,
          'facility': profile.facility,
          'specialty': profile.specialty,
        },
      });
    } catch (error, stack) {
      // Best-effort: failure here just leaves app.users stale until the next
      // attempt-submit refreshes it. The local profile is already persisted.
      developer.log(
        'profile-sync failed; server-side users row will refresh on next attempt-submit',
        name: 'LocalProfileRepository',
        error: error,
        stackTrace: stack,
      );
    }
  }
}
