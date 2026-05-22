import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';

/// Completion tiers shown as badges on the Ranked tab.
///
/// Thresholds are local to this file because nothing else needs to know them:
/// gold >= 90%, silver 70-89%, bronze 50-69%, none below.
enum RankedTier { none, bronze, silver, gold }

RankedTier rankedTierFromPercent(int percent) {
  if (percent >= 90) return RankedTier.gold;
  if (percent >= 70) return RankedTier.silver;
  if (percent >= 50) return RankedTier.bronze;
  return RankedTier.none;
}

/// Persists the best ranked score (as an integer percent 0-100) the device
/// has achieved per quiz. Updated lazily from [AttemptSubmittedEvent] for
/// `mode == 'ranked'` and cleared on [IdentityResetEvent] so a handed-over
/// device doesn't keep flashing the previous user's medals.
class RankedBestScoreStore {
  RankedBestScoreStore(this._preferences, {EventBus? eventBus}) {
    if (eventBus != null) {
      _attemptSub = eventBus
          .on<AttemptSubmittedEvent>()
          .listen(_onAttemptSubmitted);
      _identitySub =
          eventBus.on<IdentityResetEvent>().listen((_) => clear());
    }
  }

  static const String _keyPrefix = 'medrash.rankedBest.';

  final SharedPreferences _preferences;
  StreamSubscription<AttemptSubmittedEvent>? _attemptSub;
  StreamSubscription<IdentityResetEvent>? _identitySub;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Emits whenever the persisted best-score map changes (recorded or cleared).
  Stream<void> get changes => _changes.stream;

  int? bestPercentFor(String quizId) {
    final String trimmed = quizId.trim();
    if (trimmed.isEmpty) return null;
    return _preferences.getInt('$_keyPrefix$trimmed');
  }

  Map<String, int> snapshot() {
    final Map<String, int> out = <String, int>{};
    for (final String key in _preferences.getKeys()) {
      if (!key.startsWith(_keyPrefix)) continue;
      final int? value = _preferences.getInt(key);
      if (value == null) continue;
      out[key.substring(_keyPrefix.length)] = value;
    }
    return out;
  }

  /// Persists [score]/[total] as a percent if higher than the existing best.
  /// Returns true when the stored value actually changed.
  Future<bool> recordRanked(String quizId, int score, int total) async {
    final String trimmed = quizId.trim();
    if (trimmed.isEmpty || total <= 0) return false;
    final int percent = ((score / total) * 100).round().clamp(0, 100);
    final String key = '$_keyPrefix$trimmed';
    final int? existing = _preferences.getInt(key);
    if (existing != null && existing >= percent) return false;
    await _preferences.setInt(key, percent);
    if (!_changes.isClosed) _changes.add(null);
    return true;
  }

  Future<void> clear() async {
    final List<String> targets = _preferences
        .getKeys()
        .where((String k) => k.startsWith(_keyPrefix))
        .toList(growable: false);
    if (targets.isEmpty) return;
    for (final String key in targets) {
      await _preferences.remove(key);
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> _onAttemptSubmitted(AttemptSubmittedEvent event) async {
    if (event.mode != 'ranked') return;
    await recordRanked(event.quizId, event.score, event.totalQuestions);
  }

  Future<void> dispose() async {
    await _attemptSub?.cancel();
    await _identitySub?.cancel();
    await _changes.close();
  }
}
