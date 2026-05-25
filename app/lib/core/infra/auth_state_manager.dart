import 'package:flutter/foundation.dart';

import 'device_identity_service.dart';
import 'identity_snapshot.dart';
import 'identity_spine.dart';

/// Subset of profile fields required to build a resume snapshot. Kept as a
/// dedicated input so [AuthStateManager.signOut] never needs to know about
/// [ProfileRepository] (which depends on `AuthStateManager`).
class ProfileSnapshotInput {
  const ProfileSnapshotInput({
    required this.fullName,
    required this.nickname,
    required this.facility,
    required this.specialty,
    required this.totalPoints,
    required this.rank,
  });

  final String fullName;
  final String nickname;
  final String facility;
  final String specialty;
  final int totalPoints;
  final int rank;
}

class AuthStateManager extends ChangeNotifier {
  AuthStateManager({required DeviceIdentityService deviceIdentityService})
      : _deviceIdentityService = deviceIdentityService;

  final DeviceIdentityService _deviceIdentityService;

  bool _initialized = false;
  bool _hasProfile = false;
  String? _participantId;
  String? _deviceId;
  IdentitySnapshot? _lastSignedOutSnapshot;

  bool get initialized => _initialized;
  bool get hasProfile => _hasProfile;
  String? get participantId => _participantId;
  String? get deviceId => _deviceId;

  /// The most recent soft-sign-out snapshot, refreshed by [initialize] and
  /// whenever [signOut], [restoreFromSnapshot], or [dismissLastSnapshot] runs.
  /// Null when no snapshot exists or it has expired.
  IdentitySnapshot? get lastSignedOutSnapshot => _lastSignedOutSnapshot;

  IdentitySpine? get identitySpine {
    final String? deviceId = _deviceId;
    final String? participantId = _participantId;
    if (deviceId == null || participantId == null) {
      return null;
    }
    return IdentitySpine(
      deviceInstallId: deviceId,
      participantId: participantId,
      hasBoundProfile: _hasProfile,
    );
  }

  Future<void> initialize() async {
    final IdentitySpine identitySpine = await _deviceIdentityService.getIdentitySpine();
    _deviceId = identitySpine.deviceInstallId;
    _participantId = identitySpine.participantId;
    _hasProfile = identitySpine.hasBoundProfile;
    _lastSignedOutSnapshot = await _deviceIdentityService.readSnapshot();
    _initialized = true;
    notifyListeners();
  }

  Future<void> markJoined() async {
    _hasProfile = true;
    await _deviceIdentityService.setBoundProfile(true);
    notifyListeners();
  }

  /// Clears the participant binding (and optionally the device install id),
  /// then re-initialises so a fresh identity spine is minted in place.
  ///
  /// When [keepDeviceId] is true and [profile] is provided, the current
  /// spine + profile are captured to a snapshot so `/join` can offer a
  /// one-tap "Continue as @nickname" affordance. When [keepDeviceId] is
  /// false, any pre-existing snapshot is wiped — the hand-off branch is the
  /// privacy-correct break and must never leak the prior identity.
  Future<void> signOut({
    required bool keepDeviceId,
    ProfileSnapshotInput? profile,
  }) async {
    if (keepDeviceId && profile != null) {
      final String? participantId = _participantId;
      final String? deviceId = _deviceId;
      if (participantId != null && deviceId != null) {
        final IdentitySnapshot snapshot = IdentitySnapshot(
          participantId: participantId,
          deviceInstallId: deviceId,
          fullName: profile.fullName,
          nickname: profile.nickname,
          facility: profile.facility,
          specialty: profile.specialty,
          totalPoints: profile.totalPoints,
          rank: profile.rank,
          signedOutAt: DateTime.now(),
        );
        await _deviceIdentityService.writeSnapshot(snapshot);
        _lastSignedOutSnapshot = snapshot;
      }
    } else {
      await _deviceIdentityService.clearSnapshot();
      _lastSignedOutSnapshot = null;
    }

    await _deviceIdentityService.clearIdentity(keepDeviceId: keepDeviceId);
    final IdentitySpine fresh = await _deviceIdentityService.getIdentitySpine();
    _deviceId = fresh.deviceInstallId;
    _participantId = fresh.participantId;
    _hasProfile = false;
    notifyListeners();
  }

  /// Restores the device-level identity captured by [signOut]. Caller is
  /// responsible for restoring the profile fields (via `ProfileRepository`)
  /// before navigating away from `/join`.
  Future<void> restoreFromSnapshot(IdentitySnapshot snapshot) async {
    await _deviceIdentityService.restoreIdentity(snapshot);
    await _deviceIdentityService.clearSnapshot();
    _deviceId = snapshot.deviceInstallId;
    _participantId = snapshot.participantId;
    _hasProfile = true;
    _lastSignedOutSnapshot = null;
    notifyListeners();
  }

  /// User tapped "Not you? Start fresh" — drop the snapshot without touching
  /// the live identity spine.
  Future<void> dismissLastSnapshot() async {
    await _deviceIdentityService.clearSnapshot();
    _lastSignedOutSnapshot = null;
    notifyListeners();
  }

  /// Replaces the on-device participant id with one recovered from the
  /// server (slice 6b OTP rebind). The device install id is preserved
  /// because the server has already merged the freshly-minted guest user
  /// into the recovered profile; any future call from this device must
  /// resolve to the recovered participant.
  Future<void> adoptRecoveredIdentity({
    required String participantId,
    required String deviceInstallId,
  }) async {
    await _deviceIdentityService.adoptRecoveredIdentity(
      participantId: participantId,
      deviceInstallId: deviceInstallId,
    );
    await _deviceIdentityService.clearSnapshot();
    _deviceId = deviceInstallId;
    _participantId = participantId;
    _hasProfile = true;
    _lastSignedOutSnapshot = null;
    notifyListeners();
  }
}