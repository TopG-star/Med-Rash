/// Domain events emitted via [EventBus] for cross-feature coordination.
///
/// Kept intentionally tiny — one base type plus the events that have at least
/// one real listener today. Add new events here as they earn at least one
/// subscriber; do not pre-emit events that nothing listens to.
library;

abstract class MedRashEvent {
  const MedRashEvent();
}

/// Emitted by the quiz repository immediately after an attempt has been
/// successfully persisted to the backend (initial submit or retry-sync).
///
/// Listeners use this to invalidate leaderboard caches, refresh "my rank"
/// chips, and surface "saved" toasts. Never emitted for offline-practice
/// attempts (those carry `syncStatus = skipped_offline` and never POST).
class AttemptSubmittedEvent extends MedRashEvent {
  const AttemptSubmittedEvent({
    required this.quizId,
    required this.mode,
    required this.origin,
    required this.score,
    required this.totalQuestions,
    this.sessionId,
  });

  final String quizId;

  /// `'ranked'` or `'learning'`.
  final String mode;

  /// `'qr_session'` or `'open_access'`.
  final String origin;

  final int score;
  final int totalQuestions;
  final String? sessionId;
}

/// Emitted by the profile repository immediately after a profile is created
/// (quick join) or edited (settings save).
///
/// Listeners use this to invalidate leaderboard caches so a renamed
/// participant doesn't keep showing their old nickname in the standings, and
/// to trigger a best-effort server-side `profile-sync` so `app.users` matches
/// what the device just persisted.
class ProfileUpdatedEvent extends MedRashEvent {
  const ProfileUpdatedEvent({
    required this.fullName,
    required this.nickname,
    required this.facility,
    required this.specialty,
  });

  final String fullName;
  final String nickname;
  final String facility;
  final String specialty;
}

/// Emitted when the user signs out / hands the device to someone else. The
/// participant id (and optionally the device install id) has just been
/// rotated, so any cache keyed on identity — leaderboard snapshots, persisted
/// quiz attempts — must be discarded before the next read.
class IdentityResetEvent extends MedRashEvent {
  const IdentityResetEvent({required this.keptDeviceId});

  /// True when the device install id was preserved ("sign out on this
  /// device"). False when both ids were rotated ("hand to someone else").
  final bool keptDeviceId;
}

/// Emitted by the profile repository immediately after the persisted career
/// points counter has been incremented (i.e. after a ranked attempt was
/// successfully submitted and the new running total has been written to
/// shared_preferences).
///
/// Listeners use this to refresh on-screen "TOTAL POINTS" displays without
/// racing the repository's own write against [AttemptSubmittedEvent] readers.
class ProfilePointsUpdatedEvent extends MedRashEvent {
  const ProfilePointsUpdatedEvent({required this.totalPoints});

  final int totalPoints;
}

/// Emitted by [RankedBestScoreStore] when a ranked attempt crosses into a
/// higher completion tier than the device has previously recorded for that
/// quiz (e.g. first-time bronze, bronze → silver, silver → gold).
///
/// Carries the tier names as primitive strings to keep this file free of
/// feature-layer imports. Values are one of `'bronze'`, `'silver'`, `'gold'`
/// for [tier], plus `'none'` for [previousTier] when this is the first medal.
class RankedBadgeUnlockedEvent extends MedRashEvent {
  const RankedBadgeUnlockedEvent({
    required this.quizId,
    required this.tier,
    required this.previousTier,
  });

  final String quizId;
  final String tier;
  final String previousTier;
}
