import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';

/// Snapshot of the participant's engagement streak.
class StreakSnapshot {
  const StreakSnapshot({
    required this.currentStreak,
    required this.bestStreak,
    required this.lastAttemptDate,
  });

  final int currentStreak;
  final int bestStreak;
  final DateTime? lastAttemptDate;

  static const StreakSnapshot empty = StreakSnapshot(
    currentStreak: 0,
    bestStreak: 0,
    lastAttemptDate: null,
  );
}

/// Tracks how many consecutive Accra-local days the participant has submitted
/// at least one quiz attempt on. Increments lazily from
/// [AttemptSubmittedEvent]; the read path computes a live "alive vs broken"
/// streak without any background tick, so a stale streak silently resets to
/// zero as soon as the grace day passes.
///
/// Africa/Accra is GMT+0 year-round (no DST), so we bucket dates on the UTC
/// calendar instead of pulling in `package:timezone`.
///
/// Cleared on [IdentityResetEvent] so a handed-over device doesn't keep
/// flashing the previous user's streak.
class StreakStore {
  StreakStore(this._preferences, {EventBus? eventBus}) {
    if (eventBus != null) {
      _attemptSub =
          eventBus.on<AttemptSubmittedEvent>().listen(_onAttemptSubmitted);
      _identitySub =
          eventBus.on<IdentityResetEvent>().listen((_) => clear());
    }
  }

  static const String _keyCurrent = 'medrash.streak.current';
  static const String _keyBest = 'medrash.streak.best';
  static const String _keyLastDateIso = 'medrash.streak.lastDateIso';

  final SharedPreferences _preferences;
  StreamSubscription<AttemptSubmittedEvent>? _attemptSub;
  StreamSubscription<IdentityResetEvent>? _identitySub;
  final StreamController<StreakSnapshot> _changes =
      StreamController<StreakSnapshot>.broadcast();

  /// Emits the latest snapshot whenever the persisted streak changes (record
  /// or clear). UI listens to refresh "Day Streak" KPI tiles without polling.
  Stream<StreakSnapshot> get changes => _changes.stream;

  /// Read the live snapshot. If the last attempt was older than the grace
  /// day (i.e. before yesterday), the current streak is reported as zero
  /// even though the stored value hasn't been reset yet.
  StreakSnapshot read({DateTime? now}) {
    final int current = _preferences.getInt(_keyCurrent) ?? 0;
    final int best = _preferences.getInt(_keyBest) ?? 0;
    final String? lastDateIso = _preferences.getString(_keyLastDateIso);
    final DateTime? lastDate =
        lastDateIso == null ? null : DateTime.tryParse(lastDateIso);
    if (lastDate == null) {
      return StreakSnapshot(
        currentStreak: 0,
        bestStreak: best,
        lastAttemptDate: null,
      );
    }
    final DateTime today = _accraDate(now ?? DateTime.now());
    final int dayDiff = today.difference(lastDate).inDays;
    final int aliveCurrent = (dayDiff == 0 || dayDiff == 1) ? current : 0;
    return StreakSnapshot(
      currentStreak: aliveCurrent,
      bestStreak: best,
      lastAttemptDate: lastDate,
    );
  }

  /// Records that an attempt was submitted at [at]. Returns the new snapshot.
  Future<StreakSnapshot> recordAttempt({DateTime? at}) async {
    final DateTime today = _accraDate(at ?? DateTime.now());
    final int storedCurrent = _preferences.getInt(_keyCurrent) ?? 0;
    final int storedBest = _preferences.getInt(_keyBest) ?? 0;
    final String? lastIso = _preferences.getString(_keyLastDateIso);
    final DateTime? lastDate =
        lastIso == null ? null : DateTime.tryParse(lastIso);

    int newCurrent;
    if (lastDate == null) {
      newCurrent = 1;
    } else {
      final int dayDiff = today.difference(lastDate).inDays;
      if (dayDiff == 0) {
        newCurrent = storedCurrent == 0 ? 1 : storedCurrent;
      } else if (dayDiff == 1) {
        newCurrent = storedCurrent + 1;
      } else {
        // Either the streak was broken (dayDiff >= 2) or the clock went
        // backwards (dayDiff < 0). Either way, start fresh.
        newCurrent = 1;
      }
    }
    final int newBest = newCurrent > storedBest ? newCurrent : storedBest;

    await _preferences.setInt(_keyCurrent, newCurrent);
    await _preferences.setInt(_keyBest, newBest);
    await _preferences.setString(_keyLastDateIso, today.toIso8601String());

    final StreakSnapshot snap = StreakSnapshot(
      currentStreak: newCurrent,
      bestStreak: newBest,
      lastAttemptDate: today,
    );
    if (!_changes.isClosed) _changes.add(snap);
    return snap;
  }

  Future<void> clear() async {
    await _preferences.remove(_keyCurrent);
    await _preferences.remove(_keyBest);
    await _preferences.remove(_keyLastDateIso);
    if (!_changes.isClosed) _changes.add(StreakSnapshot.empty);
  }

  Future<void> _onAttemptSubmitted(AttemptSubmittedEvent _) async {
    await recordAttempt();
  }

  Future<void> dispose() async {
    await _attemptSub?.cancel();
    await _identitySub?.cancel();
    await _changes.close();
  }

  static DateTime _accraDate(DateTime instant) {
    final DateTime utc = instant.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}
