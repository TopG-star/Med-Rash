import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/features/session/storage/last_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('LastSessionStore', () {
    test('round-trips a join code within the freshness window', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LastSessionStore store = LastSessionStore(prefs);
      final DateTime now = DateTime(2026, 5, 22, 12, 0);

      await store.record('ABCD', now: now);

      final LastSessionRecord? record = store.read(now: now.add(const Duration(minutes: 30)));
      expect(record, isNotNull);
      expect(record!.joinCode, 'ABCD');
      expect(record.openedAt, now);
    });

    test('returns null once the record is older than the freshness window', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LastSessionStore store = LastSessionStore(prefs, maxAge: const Duration(hours: 2));
      final DateTime opened = DateTime(2026, 5, 22, 8, 0);

      await store.record('STALE', now: opened);

      final LastSessionRecord? record = store.read(now: opened.add(const Duration(hours: 2, minutes: 1)));
      expect(record, isNull);
    });

    test('record() trims and ignores empty input', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LastSessionStore store = LastSessionStore(prefs);

      await store.record('   ');
      expect(store.read(), isNull);

      await store.record('  WXYZ  ', now: DateTime(2026, 5, 22, 12, 0));
      final LastSessionRecord? record = store.read(now: DateTime(2026, 5, 22, 12, 1));
      expect(record?.joinCode, 'WXYZ');
    });

    test('clear() removes the persisted record', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LastSessionStore store = LastSessionStore(prefs);
      await store.record('ABCD', now: DateTime(2026, 5, 22, 12, 0));
      expect(store.read(now: DateTime(2026, 5, 22, 12, 1)), isNotNull);

      await store.clear();
      expect(store.read(now: DateTime(2026, 5, 22, 12, 1)), isNull);
    });
  });
}
