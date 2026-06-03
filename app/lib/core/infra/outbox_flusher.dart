import 'dart:async';
import 'dart:developer' as developer;

import 'medrash_http_client.dart';
import 'request_outbox.dart';

/// Drains [RequestOutbox] by replaying each queued item against
/// [MedRashHttpClient]. Removed on 2xx and on 4xx (deterministic — server
/// said no, retrying won't help). Left in place with a recorded failure on
/// network/timeout/5xx so the next flush picks it up.
///
/// Items that have failed [maxAttemptsPerItem] times are dropped to keep a
/// permanently-broken payload from blocking the queue forever.
class OutboxFlusher {
  OutboxFlusher({
    required RequestOutbox outbox,
    required MedRashHttpClient httpClient,
    this.maxAttemptsPerItem = 6,
  })  : _outbox = outbox,
        _httpClient = httpClient;

  final RequestOutbox _outbox;
  final MedRashHttpClient _httpClient;
  final int maxAttemptsPerItem;

  bool _running = false;

  /// Drain the queue. Safe to call concurrently — a second invocation while
  /// the first is in flight returns immediately.
  Future<void> flush() async {
    if (_running) return;
    _running = true;
    try {
      final List<OutboxItem> items = _outbox.peekAll();
      for (final OutboxItem item in items) {
        await _flushOne(item);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _flushOne(OutboxItem item) async {
    if (item.attempts >= maxAttemptsPerItem) {
      developer.log(
        'dropping outbox item id=${item.id} type=${item.type} after ${item.attempts} attempts',
        name: 'OutboxFlusher',
        error: item.lastError,
      );
      await _outbox.remove(item.id);
      return;
    }

    try {
      await _httpClient.postJson(
        item.type,
        item.payload,
        idempotencyKey: item.idempotencyKey,
      );
      await _outbox.remove(item.id);
    } on MedRashGateException catch (error) {
      // 4xx is deterministic — retrying won't help; drop.
      if (error.statusCode >= 400 && error.statusCode < 500) {
        developer.log(
          'dropping outbox item id=${item.id} type=${item.type} on 4xx ${error.statusCode} ${error.code}',
          name: 'OutboxFlusher',
        );
        await _outbox.remove(item.id);
        return;
      }
      await _outbox.recordFailure(item.id, 'gate ${error.statusCode}');
    } catch (error) {
      await _outbox.recordFailure(item.id, error.toString());
    }
  }
}
