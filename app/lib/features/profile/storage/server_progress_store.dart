import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/events/medrash_events.dart';
import '../../../core/infra/event_bus.dart';

/// Server-authoritative gamification snapshot (migration 021): XP, level, and
/// earned badge codes. This is the canonical source the UI reads for the XP
/// bar, level pill, and "level up" celebration — distinct from the participant
/// ranked-score total (`UserProfile.totalPoints`) and from [StreakStore] (which
/// owns the streak because it also has an offline path).
///
/// Persisted in `shared_preferences` so a cold start (before the next
/// `attempt-submit`) still paints the last-known values instead of zero.
/// Overwritten wholesale by [ServerProgressUpdatedEvent] and by
/// [adoptFromRead] (the cold-load fetch). Cleared on identity handover.
class ServerProgressSnapshot {
  const ServerProgressSnapshot({
    required this.xp,
    required this.level,
    required this.earnedBadgeCodes,
  });

  final int xp;
  final int level;
  final List<String> earnedBadgeCodes;

  /// XP into the current level and the span of the current level, derived from
  /// the same 250-XP curve as `app.level_for_xp`. Used to fill the XP bar.
  int get xpIntoLevel => xp % _xpPerLevel;
  int get xpToNextLevel => _xpPerLevel - xpIntoLevel;
  double get levelProgress => xpIntoLevel / _xpPerLevel;

  static const int _xpPerLevel = 250;

  static const ServerProgressSnapshot empty = ServerProgressSnapshot(
    xp: 0,
    level: 1,
    earnedBadgeCodes: <String>[],
  );
}

class ServerProgressStore {
  ServerProgressStore(this._preferences, {EventBus? eventBus}) {
    if (eventBus != null) {
      _progressSub =
          eventBus.on<ServerProgressUpdatedEvent>().listen(_onServerProgress);
      _identitySub = eventBus.on<IdentityResetEvent>().listen((_) => clear());
    }
  }

  static const String _keyXp = 'medrash.progress.xp';
  static const String _keyLevel = 'medrash.progress.level';
  static const String _keyBadges = 'medrash.progress.badges';

  final SharedPreferences _preferences;
  StreamSubscription<ServerProgressUpdatedEvent>? _progressSub;
  StreamSubscription<IdentityResetEvent>? _identitySub;
  final StreamController<ServerProgressSnapshot> _changes =
      StreamController<ServerProgressSnapshot>.broadcast();

  /// Emits whenever the persisted snapshot changes. UI listens to refresh the
  /// XP bar / level pill without polling.
  Stream<ServerProgressSnapshot> get changes => _changes.stream;

  ServerProgressSnapshot read() {
    final int? xp = _preferences.getInt(_keyXp);
    if (xp == null) return ServerProgressSnapshot.empty;
    return ServerProgressSnapshot(
      xp: xp,
      level: _preferences.getInt(_keyLevel) ?? 1,
      earnedBadgeCodes:
          _preferences.getStringList(_keyBadges) ?? const <String>[],
    );
  }

  /// Adopt values from a cold-load read (the `progress-get` endpoint). Merges
  /// the returned badge list into whatever is stored so a stale local list
  /// never drops a badge the server knows about.
  Future<ServerProgressSnapshot> adoptFromRead({
    required int xp,
    required int level,
    required List<String> earnedBadgeCodes,
  }) async {
    return _write(xp: xp, level: level, earnedBadgeCodes: earnedBadgeCodes);
  }

  Future<void> clear() async {
    await _preferences.remove(_keyXp);
    await _preferences.remove(_keyLevel);
    await _preferences.remove(_keyBadges);
    if (!_changes.isClosed) _changes.add(ServerProgressSnapshot.empty);
  }

  Future<void> _onServerProgress(ServerProgressUpdatedEvent e) async {
    // Union the newly-earned codes with what we already had — the submit
    // response only reports deltas, not the full collection.
    final Set<String> merged = <String>{
      ..._preferences.getStringList(_keyBadges) ?? const <String>[],
      ...e.newlyEarned,
    };
    await _write(
      xp: e.xp,
      level: e.level,
      earnedBadgeCodes: merged.toList(growable: false),
    );
  }

  Future<ServerProgressSnapshot> _write({
    required int xp,
    required int level,
    required List<String> earnedBadgeCodes,
  }) async {
    await _preferences.setInt(_keyXp, xp);
    await _preferences.setInt(_keyLevel, level);
    await _preferences.setStringList(_keyBadges, earnedBadgeCodes);
    final ServerProgressSnapshot snap = ServerProgressSnapshot(
      xp: xp,
      level: level,
      earnedBadgeCodes: earnedBadgeCodes,
    );
    if (!_changes.isClosed) _changes.add(snap);
    return snap;
  }

  Future<void> dispose() async {
    await _progressSub?.cancel();
    await _identitySub?.cancel();
    await _changes.close();
  }
}
