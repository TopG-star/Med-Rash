import 'package:shared_preferences/shared_preferences.dart';

/// Most recent session join the device opened, kept locally so the home
/// screen can offer a "Continue last session" shortcut without a server call.
class LastSessionRecord {
  const LastSessionRecord({
    required this.joinCode,
    required this.openedAt,
    this.sessionId,
  });

  final String joinCode;
  final DateTime openedAt;

  /// Server-side session UUID. Optional because older records (pre-Slice
  /// session-leaderboard) only stored the joinCode; consumers must null-check
  /// before deep-linking to the per-session leaderboard.
  final String? sessionId;
}

/// Persists the last opened session join code with a timestamp in
/// `shared_preferences`. Reads return `null` once the record is older than
/// [maxAge] so stale sessions don't keep nagging the user from the home card.
class LastSessionStore {
  LastSessionStore(this._preferences, {Duration maxAge = const Duration(hours: 2)})
      : _maxAge = maxAge;

  static const String _keyJoinCode = 'medrash.lastSession.joinCode';
  static const String _keyOpenedAtMs = 'medrash.lastSession.openedAtMs';
  static const String _keySessionId = 'medrash.lastSession.sessionId';

  final SharedPreferences _preferences;
  final Duration _maxAge;

  Future<void> record(
    String joinCode, {
    DateTime? now,
    String? sessionId,
  }) async {
    final String trimmed = joinCode.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final DateTime stamp = now ?? DateTime.now();
    await _preferences.setString(_keyJoinCode, trimmed);
    await _preferences.setInt(_keyOpenedAtMs, stamp.millisecondsSinceEpoch);
    final String? trimmedSessionId = sessionId?.trim();
    if (trimmedSessionId != null && trimmedSessionId.isNotEmpty) {
      await _preferences.setString(_keySessionId, trimmedSessionId);
    } else {
      // Clear any stale sessionId so we never deep-link the wrong board.
      await _preferences.remove(_keySessionId);
    }
  }

  LastSessionRecord? read({DateTime? now}) {
    final String? joinCode = _preferences.getString(_keyJoinCode);
    final int? openedAtMs = _preferences.getInt(_keyOpenedAtMs);
    if (joinCode == null || joinCode.isEmpty || openedAtMs == null) {
      return null;
    }
    final DateTime openedAt = DateTime.fromMillisecondsSinceEpoch(openedAtMs);
    final DateTime cutoff = (now ?? DateTime.now()).subtract(_maxAge);
    if (openedAt.isBefore(cutoff)) {
      return null;
    }
    final String? sessionId = _preferences.getString(_keySessionId);
    return LastSessionRecord(
      joinCode: joinCode,
      openedAt: openedAt,
      sessionId: (sessionId != null && sessionId.isNotEmpty) ? sessionId : null,
    );
  }

  Future<void> clear() async {
    await _preferences.remove(_keyJoinCode);
    await _preferences.remove(_keyOpenedAtMs);
    await _preferences.remove(_keySessionId);
  }
}
