import 'package:shared_preferences/shared_preferences.dart';

/// Most recent session join the device opened, kept locally so the home
/// screen can offer a "Continue last session" shortcut without a server call.
class LastSessionRecord {
  const LastSessionRecord({required this.joinCode, required this.openedAt});

  final String joinCode;
  final DateTime openedAt;
}

/// Persists the last opened session join code with a timestamp in
/// `shared_preferences`. Reads return `null` once the record is older than
/// [maxAge] so stale sessions don't keep nagging the user from the home card.
class LastSessionStore {
  LastSessionStore(this._preferences, {Duration maxAge = const Duration(hours: 2)})
      : _maxAge = maxAge;

  static const String _keyJoinCode = 'medrash.lastSession.joinCode';
  static const String _keyOpenedAtMs = 'medrash.lastSession.openedAtMs';

  final SharedPreferences _preferences;
  final Duration _maxAge;

  Future<void> record(String joinCode, {DateTime? now}) async {
    final String trimmed = joinCode.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final DateTime stamp = now ?? DateTime.now();
    await _preferences.setString(_keyJoinCode, trimmed);
    await _preferences.setInt(_keyOpenedAtMs, stamp.millisecondsSinceEpoch);
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
    return LastSessionRecord(joinCode: joinCode, openedAt: openedAt);
  }

  Future<void> clear() async {
    await _preferences.remove(_keyJoinCode);
    await _preferences.remove(_keyOpenedAtMs);
  }
}
