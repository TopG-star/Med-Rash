import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';

/// Tracks whether a guest participant (nickname matching
/// [ProfileRepository.isGuestNickname]) has already played a round on this
/// device and whether they've dismissed the "Complete your profile" banner.
///
/// The banner is surfaced on Home (mode selection) and on the Ranked Mode
/// page so the participant is gently nudged to swap their `Guest-####`
/// alias for a real name + facility — without ever blocking play.
///
/// Persistence is local-only (`shared_preferences`); a sign-out resets the
/// store via [reset] so the next user of the device starts clean.
class GuestProfilePromptStore extends ChangeNotifier {
  GuestProfilePromptStore(this._preferences, {EventBus? eventBus})
      : _eventBus = eventBus {
    _attemptSub = eventBus?.on<AttemptSubmittedEvent>().listen((_) {
      _markPlayed();
    });
    _profileSub = eventBus?.on<ProfileUpdatedEvent>().listen((event) {
      // If the participant now has a real nickname (no longer Guest-####),
      // they've fulfilled the ask — wipe the flags so the banner doesn't
      // come back on a subsequent guest mint after sign-out.
      if (!ProfileRepository.isGuestNickname(event.nickname)) {
        unawaited(reset());
      }
    });
    _identitySub = eventBus?.on<IdentityResetEvent>().listen((_) {
      // New device owner: start fresh.
      unawaited(reset());
    });
  }

  static const String _keyPlayedAtMs = 'medrash.guestPrompt.playedAtMs';
  static const String _keyDismissedAtMs = 'medrash.guestPrompt.dismissedAtMs';

  final SharedPreferences _preferences;
  // Kept so the store owns its subscriptions over the singleton lifetime;
  // ignored on dispose since the store outlives every widget.
  // ignore: unused_field
  final EventBus? _eventBus;
  StreamSubscription<AttemptSubmittedEvent>? _attemptSub;
  StreamSubscription<ProfileUpdatedEvent>? _profileSub;
  StreamSubscription<IdentityResetEvent>? _identitySub;

  bool get _hasPlayed => _preferences.getInt(_keyPlayedAtMs) != null;
  bool get _isDismissed => _preferences.getInt(_keyDismissedAtMs) != null;

  /// True when [profile] is a non-null guest who has finished at least one
  /// attempt and not yet dismissed the banner. Widgets call this on every
  /// rebuild and re-evaluate when the store [notifyListeners].
  bool shouldShow(UserProfile? profile) {
    if (profile == null) return false;
    if (!ProfileRepository.isGuestNickname(profile.nickname)) return false;
    return _hasPlayed && !_isDismissed;
  }

  Future<void> _markPlayed() async {
    if (_hasPlayed) return;
    await _preferences.setInt(
      _keyPlayedAtMs,
      DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  /// User tapped the dismiss icon on the banner. Hides it on every surface
  /// until [reset] is called (sign-out or successful profile completion).
  Future<void> dismiss() async {
    if (_isDismissed) return;
    await _preferences.setInt(
      _keyDismissedAtMs,
      DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  /// Wipe both flags. Invoked on sign-out and when the participant graduates
  /// from a guest nickname to a real profile.
  Future<void> reset() async {
    await _preferences.remove(_keyPlayedAtMs);
    await _preferences.remove(_keyDismissedAtMs);
    notifyListeners();
  }

  @override
  void dispose() {
    _attemptSub?.cancel();
    _identitySub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
