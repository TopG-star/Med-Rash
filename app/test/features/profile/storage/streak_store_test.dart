import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medrash_app/features/profile/storage/streak_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<StreakStore> makeStore() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return StreakStore(prefs);
  }

  group('StreakStore', () {
    test('starts at zero with no last date', () async {
      final StreakStore store = await makeStore();
      final StreakSnapshot snap = store.read(now: DateTime.utc(2026, 5, 26));
      expect(snap.currentStreak, 0);
      expect(snap.bestStreak, 0);
      expect(snap.lastAttemptDate, isNull);
    });

    test('first attempt sets current and best to 1', () async {
      final StreakStore store = await makeStore();
      final StreakSnapshot snap =
          await store.recordAttempt(at: DateTime.utc(2026, 5, 26, 9));
      expect(snap.currentStreak, 1);
      expect(snap.bestStreak, 1);
    });

    test('same-day second attempt does not increment current', () async {
      final StreakStore store = await makeStore();
      await store.recordAttempt(at: DateTime.utc(2026, 5, 26, 9));
      final StreakSnapshot snap =
          await store.recordAttempt(at: DateTime.utc(2026, 5, 26, 23));
      expect(snap.currentStreak, 1);
      expect(snap.bestStreak, 1);
    });

    test('consecutive-day attempt increments and updates best', () async {
      final StreakStore store = await makeStore();
      await store.recordAttempt(at: DateTime.utc(2026, 5, 25, 8));
      final StreakSnapshot snap =
          await store.recordAttempt(at: DateTime.utc(2026, 5, 26, 8));
      expect(snap.currentStreak, 2);
      expect(snap.bestStreak, 2);
    });

    test('gap of 2+ days resets current but keeps best', () async {
      final StreakStore store = await makeStore();
      await store.recordAttempt(at: DateTime.utc(2026, 5, 20));
      await store.recordAttempt(at: DateTime.utc(2026, 5, 21));
      await store.recordAttempt(at: DateTime.utc(2026, 5, 22));
      final StreakSnapshot snap =
          await store.recordAttempt(at: DateTime.utc(2026, 5, 26));
      expect(snap.currentStreak, 1);
      expect(snap.bestStreak, 3);
    });

    test('read reports zero current after the grace day passes', () async {
      final StreakStore store = await makeStore();
      await store.recordAttempt(at: DateTime.utc(2026, 5, 20));
      // Read 3 days later — last attempt was older than yesterday.
      final StreakSnapshot snap = store.read(now: DateTime.utc(2026, 5, 23));
      expect(snap.currentStreak, 0);
      expect(snap.bestStreak, 1);
      expect(snap.lastAttemptDate, DateTime.utc(2026, 5, 20));
    });

    test('read still reports current on the grace day (lastDate=yesterday)',
        () async {
      final StreakStore store = await makeStore();
      await store.recordAttempt(at: DateTime.utc(2026, 5, 25, 23));
      final StreakSnapshot snap =
          store.read(now: DateTime.utc(2026, 5, 26, 5));
      expect(snap.currentStreak, 1);
    });

    test('clear wipes all counters', () async {
      final StreakStore store = await makeStore();
      await store.recordAttempt(at: DateTime.utc(2026, 5, 26));
      await store.clear();
      final StreakSnapshot snap = store.read(now: DateTime.utc(2026, 5, 26));
      expect(snap.currentStreak, 0);
      expect(snap.bestStreak, 0);
      expect(snap.lastAttemptDate, isNull);
    });
  });
}
