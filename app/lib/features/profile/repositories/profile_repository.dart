import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/events/medrash_events.dart';
import '../../../core/infra/auth_state_manager.dart';
import '../../../core/infra/event_bus.dart';
import '../../../core/infra/identity_snapshot.dart';
import '../../../core/infra/medrash_http_client.dart';
import '../models/user_profile.dart';

/// Raised when the server rejects a profile sync because another `app.users`
/// row already owns the supplied recovery email. The UI catches this from
/// [ProfileRepository.quickJoin] and prompts the participant to pick a
/// different email (or clear it and continue without recovery).
class EmailTakenException implements Exception {
  const EmailTakenException(this.message);
  final String message;
  @override
  String toString() => 'EmailTakenException: $message';
}

abstract class ProfileRepository {
  Future<UserProfile?> getProfile();

  /// Persists the onboarding profile locally and (when [email] is non-empty)
  /// awaits the server sync so an `EMAIL_TAKEN` collision surfaces to the
  /// caller as [EmailTakenException] before the user leaves the screen.
  /// When [email] is null/empty the sync remains best-effort.
  Future<UserProfile> quickJoin({
    required String fullName,
    required String facility,
    required String specialty,
    String? nickname,
    String? email,
  });

  /// Silently mint a guest profile so a QR-deep-link visitor can land on a
  /// session screen without filling the quick-join form (Slice 3 / Option B
  /// fast-join). The minted nickname matches [isGuestNickname], which the UI
  /// uses to surface an inline "Pick a nickname" prompt before ranked play.
  Future<UserProfile> mintGuestProfile({int? seedSuffix});

  /// True for nicknames produced by [mintGuestProfile] (`Guest-1234`). The
  /// UI uses this to decide whether to show the rename prompt and to gate
  /// the ranked CTA.
  static bool isGuestNickname(String nickname) {
    return RegExp(r'^Guest-\d{3,4}$').hasMatch(nickname.trim());
  }

  Future<UserProfile> updateProfile({
    required String nickname,
    required String facility,
    required String specialty,
  });

  /// Wipe every `medrash.profile.*` key. Used by sign-out so the next user of
  /// this device starts at the quick-join screen with a blank slate.
  Future<void> clearAll();

  /// Re-populate every `medrash.profile.*` key from a sign-out snapshot so a
  /// returning user lands on `/home` with their nickname, facility, specialty
  /// and cached points intact. The server-side row is re-attached via the
  /// restored `participant_id`; the next leaderboard/attempt response will
  /// reconcile any drift in points/rank.
  Future<UserProfile> restoreFromSnapshot(IdentitySnapshot snapshot);

  /// Persists a profile recovered from the server (slice 6b OTP rebind).
  /// Unlike [quickJoin] this never POSTs to profile-sync — the recovered row
  /// already exists server-side. Points/rank reset to zero locally and will
  /// be reconciled by the next leaderboard fetch.
  Future<UserProfile> persistRecoveredProfile(UserProfile profile);

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
  static const String _keyEmail = 'medrash.profile.email';

  @override
  Future<UserProfile?> getProfile() async {
    final String? fullName = _preferences.getString(_keyFullName);
    if (fullName == null || fullName.isEmpty) {
      return null;
    }

    final String? storedEmail = _preferences.getString(_keyEmail);
    return UserProfile(
      fullName: fullName,
      nickname: _preferences.getString(_keyNickname) ?? generateNickname(fullName: fullName),
      facility: _preferences.getString(_keyFacility) ?? '',
      specialty: _preferences.getString(_keySpecialty) ?? 'Doctor',
      totalPoints: _preferences.getInt(_keyTotalPoints) ?? 0,
      rank: _preferences.getInt(_keyRank) ?? 0,
      email: (storedEmail == null || storedEmail.isEmpty) ? null : storedEmail,
    );
  }

  @override
  Future<UserProfile> quickJoin({
    required String fullName,
    required String facility,
    required String specialty,
    String? nickname,
    String? email,
  }) async {
    final String generatedNickname = nickname?.trim().isNotEmpty == true
        ? nickname!.trim()
        : generateNickname(fullName: fullName);

    const int seedPoints = 0;
    const int seedRank = 0;
    final String? normalizedEmail =
        (email == null || email.trim().isEmpty) ? null : email.trim().toLowerCase();

    await _preferences.setString(_keyFullName, fullName.trim());
    await _preferences.setString(_keyFacility, facility.trim());
    await _preferences.setString(_keySpecialty, specialty.trim());
    await _preferences.setString(_keyNickname, generatedNickname);
    await _preferences.setInt(_keyTotalPoints, seedPoints);
    await _preferences.setInt(_keyRank, seedRank);
    if (normalizedEmail == null) {
      await _preferences.remove(_keyEmail);
    } else {
      await _preferences.setString(_keyEmail, normalizedEmail);
    }

    final UserProfile profile = UserProfile(
      fullName: fullName.trim(),
      nickname: generatedNickname,
      facility: facility.trim(),
      specialty: specialty.trim(),
      totalPoints: seedPoints,
      rank: seedRank,
      email: normalizedEmail,
    );

    // When the user opted into recovery, await the sync so an EMAIL_TAKEN
    // collision surfaces as EmailTakenException before navigation. When no
    // email was supplied we keep the historic best-effort behaviour: emit
    // the event and let the background sync run.
    if (normalizedEmail != null) {
      _eventBus?.emit(ProfileUpdatedEvent(
        fullName: profile.fullName,
        nickname: profile.nickname,
        facility: profile.facility,
        specialty: profile.specialty,
      ));
      await _syncProfileToServer(profile, rethrowTaken: true);
    } else {
      _broadcastProfileUpdate(profile);
    }
    return profile;
  }

  @override
  Future<UserProfile> mintGuestProfile({int? seedSuffix}) async {
    final int suffix = seedSuffix ?? (Random().nextInt(9000) + 1000);
    final String nickname = 'Guest-$suffix';
    return quickJoin(
      fullName: nickname,
      facility: '',
      specialty: 'Doctor',
      nickname: nickname,
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
    await _preferences.remove(_keyEmail);
  }

  @override
  Future<UserProfile> restoreFromSnapshot(IdentitySnapshot snapshot) async {
    await _preferences.setString(_keyFullName, snapshot.fullName);
    await _preferences.setString(_keyNickname, snapshot.nickname);
    await _preferences.setString(_keyFacility, snapshot.facility);
    await _preferences.setString(_keySpecialty, snapshot.specialty);
    await _preferences.setInt(_keyTotalPoints, snapshot.totalPoints);
    await _preferences.setInt(_keyRank, snapshot.rank);

    final UserProfile profile = UserProfile(
      fullName: snapshot.fullName,
      nickname: snapshot.nickname,
      facility: snapshot.facility,
      specialty: snapshot.specialty,
      totalPoints: snapshot.totalPoints,
      rank: snapshot.rank,
    );
    _broadcastProfileUpdate(profile);
    return profile;
  }

  @override
  Future<UserProfile> persistRecoveredProfile(UserProfile profile) async {
    await _preferences.setString(_keyFullName, profile.fullName);
    await _preferences.setString(_keyNickname, profile.nickname);
    await _preferences.setString(_keyFacility, profile.facility);
    await _preferences.setString(_keySpecialty, profile.specialty);
    // Points + rank start at 0 locally; the next leaderboard fetch fills the
    // real numbers in. We don't trust whatever the recover-verify payload
    // sent because the server-truth view is the leaderboard.
    await _preferences.setInt(_keyTotalPoints, 0);
    await _preferences.setInt(_keyRank, 0);
    final String? email = profile.email;
    if (email == null || email.isEmpty) {
      await _preferences.remove(_keyEmail);
    } else {
      await _preferences.setString(_keyEmail, email);
    }

    // Emit but do NOT trigger a server sync — the recovered row already
    // exists and we'd just round-trip the same data.
    _eventBus?.emit(ProfileUpdatedEvent(
      fullName: profile.fullName,
      nickname: profile.nickname,
      facility: profile.facility,
      specialty: profile.specialty,
    ));
    return profile;
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

  Future<void> _syncProfileToServer(
    UserProfile profile, {
    bool rethrowTaken = false,
  }) async {
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
          // Only include `email` when the local profile actually carries one
          // so an unrelated profile edit (e.g. nickname change) never clears
          // a previously-saved recovery email server-side.
          if (profile.email != null && profile.email!.isNotEmpty) 'email': profile.email,
        },
      });
    } on MedRashGateException catch (error, stack) {
      if (rethrowTaken && error.code == 'EMAIL_TAKEN') {
        final String? serverMessage = error.body['message']?.toString();
        throw EmailTakenException(
          (serverMessage != null && serverMessage.isNotEmpty)
              ? serverMessage
              : 'That email is already linked to another profile.',
        );
      }
      developer.log(
        'profile-sync failed; server-side users row will refresh on next attempt-submit',
        name: 'LocalProfileRepository',
        error: error,
        stackTrace: stack,
      );
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
