import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/infra/request_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RequestOutbox', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('enqueue assigns monotonic ids and survives reload', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RequestOutbox outbox = RequestOutbox(prefs);

      final int id1 = await outbox.enqueue(
        type: 'profile-sync',
        idempotencyKey: 'p1',
        payload: <String, Object?>{'a': 1},
      );
      final int id2 = await outbox.enqueue(
        type: 'profile-sync',
        idempotencyKey: 'p2',
        payload: <String, Object?>{'a': 2},
      );

      expect(id1, 1);
      expect(id2, 2);

      final RequestOutbox reload = RequestOutbox(prefs);
      final List<OutboxItem> items = reload.peekAll();
      expect(items.length, 2);
      expect(items[0].payload['a'], 1);
      expect(items[1].payload['a'], 2);
    });

    test('enqueue with duplicate idempotencyKey replaces existing entry',
        () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RequestOutbox outbox = RequestOutbox(prefs);

      await outbox.enqueue(
        type: 'profile-sync',
        idempotencyKey: 'same',
        payload: <String, Object?>{'v': 'first'},
      );
      await outbox.enqueue(
        type: 'profile-sync',
        idempotencyKey: 'same',
        payload: <String, Object?>{'v': 'second'},
      );

      final List<OutboxItem> items = outbox.peekAll();
      expect(items.length, 1);
      expect(items.single.payload['v'], 'second');
    });

    test('remove deletes the item by id', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RequestOutbox outbox = RequestOutbox(prefs);
      final int id = await outbox.enqueue(
        type: 't',
        idempotencyKey: 'k',
        payload: <String, Object?>{},
      );

      await outbox.remove(id);
      expect(outbox.peekAll(), isEmpty);
    });

    test('recordFailure increments attempts and stores lastError', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RequestOutbox outbox = RequestOutbox(prefs);
      final int id = await outbox.enqueue(
        type: 't',
        idempotencyKey: 'k',
        payload: <String, Object?>{},
      );

      await outbox.recordFailure(id, 'boom');
      await outbox.recordFailure(id, 'boom2');

      final OutboxItem item = outbox.peekAll().single;
      expect(item.attempts, 2);
      expect(item.lastError, 'boom2');
    });

    test('cap drops oldest and increments droppedCount', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RequestOutbox outbox = RequestOutbox(prefs, maxItems: 3);

      for (int i = 0; i < 5; i += 1) {
        await outbox.enqueue(
          type: 't',
          idempotencyKey: 'k$i',
          payload: <String, Object?>{'i': i},
        );
      }

      final List<OutboxItem> items = outbox.peekAll();
      expect(items.length, 3);
      expect(items.first.payload['i'], 2);
      expect(items.last.payload['i'], 4);
      expect(outbox.droppedCount, 2);
    });
  });
}
