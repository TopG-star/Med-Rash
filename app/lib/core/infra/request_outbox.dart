import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted FIFO outbox for fire-and-forget Netlify function writes that
/// must survive a tab kill / refresh / process death.
///
/// Shape under SharedPreferences key [_storageKey]:
///
/// ```json
/// {
///   "v": 1,
///   "nextId": 17,
///   "droppedCount": 0,
///   "items": [
///     { "id": 14, "type": "profile-sync", "idempotencyKey": "...",
///       "createdAt": 1717000000000, "payload": {...},
///       "attempts": 0, "lastError": null }
///   ]
/// }
/// ```
///
/// Capped at [maxItems] entries AND [maxSerializedBytes] serialized bytes
/// (whichever trips first). On overflow the oldest item is dropped and
/// `droppedCount` is incremented — visible via [droppedCount] for any
/// future telemetry. SharedPreferences is not a database; the cap is what
/// keeps this safe at pilot scale.
class RequestOutbox {
  RequestOutbox(
    this._preferences, {
    this.maxItems = 200,
    this.maxSerializedBytes = 256 * 1024,
  });

  static const String _storageKey = 'medrash.outbox.v1';
  static const int _schemaVersion = 1;

  final SharedPreferences _preferences;
  final int maxItems;
  final int maxSerializedBytes;

  /// Append a request. If an item with the same [idempotencyKey] is already
  /// queued, the existing entry is replaced (latest payload wins) instead of
  /// adding a duplicate. Returns the assigned item id.
  Future<int> enqueue({
    required String type,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    final _OutboxState state = _readState();

    state.items.removeWhere(
      (OutboxItem existing) => existing.idempotencyKey == idempotencyKey,
    );

    final int id = state.nextId;
    state.nextId = id + 1;
    state.items.add(
      OutboxItem(
        id: id,
        type: type,
        idempotencyKey: idempotencyKey,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        payload: payload,
        attempts: 0,
        lastError: null,
      ),
    );

    _compact(state);
    await _writeState(state);
    return id;
  }

  /// Snapshot of the current queue. Safe to iterate; the underlying store is
  /// not mutated.
  List<OutboxItem> peekAll() => List<OutboxItem>.unmodifiable(_readState().items);

  /// Number of items dropped due to cap overflow since the outbox was first
  /// created. Exposed for telemetry / debug surfaces.
  int get droppedCount => _readState().droppedCount;

  /// Remove the item with [id] from the queue. No-op if it has already been
  /// flushed by a concurrent pass.
  Future<void> remove(int id) async {
    final _OutboxState state = _readState();
    final int before = state.items.length;
    state.items.removeWhere((OutboxItem item) => item.id == id);
    if (state.items.length == before) {
      return;
    }
    await _writeState(state);
  }

  /// Mark an item as having failed another flush attempt. Increments
  /// `attempts` and records [error]. Used so callers can decide to give up
  /// (e.g. after N attempts).
  Future<void> recordFailure(int id, String error) async {
    final _OutboxState state = _readState();
    final int idx = state.items.indexWhere((OutboxItem item) => item.id == id);
    if (idx < 0) {
      return;
    }
    final OutboxItem prev = state.items[idx];
    state.items[idx] = OutboxItem(
      id: prev.id,
      type: prev.type,
      idempotencyKey: prev.idempotencyKey,
      createdAt: prev.createdAt,
      payload: prev.payload,
      attempts: prev.attempts + 1,
      lastError: error,
    );
    await _writeState(state);
  }

  /// Wipe the queue. Test / debug only.
  Future<void> clear() async {
    await _preferences.remove(_storageKey);
  }

  void _compact(_OutboxState state) {
    while (state.items.length > maxItems) {
      state.items.removeAt(0);
      state.droppedCount += 1;
    }
    // Serialized byte cap. Encode and trim oldest until under budget. We
    // recompute each loop rather than estimating per-item so nested payloads
    // are accounted for accurately.
    while (state.items.isNotEmpty &&
        _serialize(state).codeUnits.length > maxSerializedBytes) {
      state.items.removeAt(0);
      state.droppedCount += 1;
    }
  }

  _OutboxState _readState() {
    final String? raw = _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return _OutboxState.empty();
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return _OutboxState.empty();
      }
      final int v = (decoded['v'] as num?)?.toInt() ?? 0;
      if (v != _schemaVersion) {
        developer.log(
          'outbox schema mismatch (got $v, expected $_schemaVersion); discarding',
          name: 'RequestOutbox',
        );
        return _OutboxState.empty();
      }
      final List<dynamic> rawItems =
          (decoded['items'] as List<dynamic>?) ?? <dynamic>[];
      final List<OutboxItem> items = <OutboxItem>[];
      for (final dynamic raw in rawItems) {
        if (raw is! Map<String, Object?>) continue;
        final OutboxItem? item = OutboxItem.fromJson(raw);
        if (item != null) items.add(item);
      }
      return _OutboxState(
        nextId: (decoded['nextId'] as num?)?.toInt() ?? items.length,
        droppedCount: (decoded['droppedCount'] as num?)?.toInt() ?? 0,
        items: items,
      );
    } catch (error, stack) {
      developer.log(
        'outbox decode failed; discarding queue',
        name: 'RequestOutbox',
        error: error,
        stackTrace: stack,
      );
      return _OutboxState.empty();
    }
  }

  Future<void> _writeState(_OutboxState state) async {
    final String encoded = _serialize(state);
    await _preferences.setString(_storageKey, encoded);
  }

  String _serialize(_OutboxState state) => jsonEncode(<String, Object?>{
        'v': _schemaVersion,
        'nextId': state.nextId,
        'droppedCount': state.droppedCount,
        'items': state.items.map((OutboxItem i) => i.toJson()).toList(),
      });
}

class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.type,
    required this.idempotencyKey,
    required this.createdAt,
    required this.payload,
    required this.attempts,
    required this.lastError,
  });

  final int id;
  final String type;
  final String idempotencyKey;
  final int createdAt;
  final Map<String, Object?> payload;
  final int attempts;
  final String? lastError;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        'idempotencyKey': idempotencyKey,
        'createdAt': createdAt,
        'payload': payload,
        'attempts': attempts,
        'lastError': lastError,
      };

  static OutboxItem? fromJson(Map<String, Object?> j) {
    try {
      final Object? payload = j['payload'];
      if (payload is! Map<String, Object?>) return null;
      return OutboxItem(
        id: (j['id'] as num).toInt(),
        type: j['type'] as String,
        idempotencyKey: j['idempotencyKey'] as String,
        createdAt: (j['createdAt'] as num).toInt(),
        payload: payload,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastError: j['lastError'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class _OutboxState {
  _OutboxState({
    required this.nextId,
    required this.droppedCount,
    required this.items,
  });

  factory _OutboxState.empty() => _OutboxState(
        nextId: 1,
        droppedCount: 0,
        items: <OutboxItem>[],
      );

  int nextId;
  int droppedCount;
  final List<OutboxItem> items;
}
