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

/// Emitted by the quiz repository when `attempt-submit` returns a
/// server-authoritative gamification `progress` block (migration 021). This is
/// the canonical source of XP / streak / level / badges — it overrides the
/// device-local [StreakStore] and career-points guesses, which remain only as
/// an offline fallback until the next successful sync.
///
/// Fields mirror the RPC `app.record_attempt_progress` return shape. Carries
/// primitives + a `List<String>` of newly-earned badge codes to keep this file
/// free of feature-layer imports.
class ServerProgressUpdatedEvent extends MedRashEvent {
  const ServerProgressUpdatedEvent({
    required this.xp,
    required this.level,
    required this.currentStreak,
    required this.bestStreak,
    required this.xpGained,
    required this.leveledUp,
    required this.newlyEarned,
  });

  /// Builds an event from the raw `progress` JSON returned by the gate, or
  /// `null` when the block is absent/malformed (older server, RPC failure).
  static ServerProgressUpdatedEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? xp = raw['xp'];
    final Object? streak = raw['current_streak'];
    // xp + current_streak are the load-bearing fields; bail if either is missing.
    if (xp is! num || streak is! num) return null;
    final Object? earnedRaw = raw['newly_earned'];
    final List<String> earned = earnedRaw is List
        ? earnedRaw.whereType<String>().toList(growable: false)
        : const <String>[];
    return ServerProgressUpdatedEvent(
      xp: xp.toInt(),
      level: (raw['level'] as num?)?.toInt() ?? 1,
      currentStreak: streak.toInt(),
      bestStreak: (raw['best_streak'] as num?)?.toInt() ?? streak.toInt(),
      xpGained: (raw['xp_gained'] as num?)?.toInt() ?? 0,
      leveledUp: raw['leveled_up'] == true,
      newlyEarned: earned,
    );
  }

  final int xp;
  final int level;
  final int currentStreak;
  final int bestStreak;
  final int xpGained;
  final bool leveledUp;
  final List<String> newlyEarned;
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
