import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medrash_app/core/events/medrash_events.dart';
import 'package:medrash_app/features/profile/storage/server_progress_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ServerProgressStore> makeStore() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return ServerProgressStore(prefs);
  }

  group('ServerProgressUpdatedEvent.fromJson', () {
    test('parses a well-formed block', () {
      final ServerProgressUpdatedEvent? e =
          ServerProgressUpdatedEvent.fromJson(<String, Object?>{
        'xp': 340,
        'level': 2,
        'current_streak': 12,
        'best_streak': 30,
        'xp_gained': 50,
        'leveled_up': true,
        'newly_earned': <String>['first_win', 'streak_3'],
      });
      expect(e, isNotNull);
      expect(e!.xp, 340);
      expect(e.level, 2);
      expect(e.currentStreak, 12);
      expect(e.bestStreak, 30);
      expect(e.xpGained, 50);
      expect(e.leveledUp, isTrue);
      expect(e.newlyEarned, <String>['first_win', 'streak_3']);
    });

    test('returns null when load-bearing fields are missing', () {
      expect(ServerProgressUpdatedEvent.fromJson(null), isNull);
      expect(ServerProgressUpdatedEvent.fromJson('not a map'), isNull);
      expect(
        ServerProgressUpdatedEvent.fromJson(<String, Object?>{'level': 2}),
        isNull,
      );
    });

    test('defaults optional fields and filters non-string badge codes', () {
      final ServerProgressUpdatedEvent? e =
          ServerProgressUpdatedEvent.fromJson(<String, Object?>{
        'xp': 10,
        'current_streak': 1,
        // level, best_streak, xp_gained, leveled_up omitted
        'newly_earned': <Object?>['ok', 42, null],
      });
      expect(e, isNotNull);
      expect(e!.level, 1);
      expect(e.bestStreak, 1); // falls back to current_streak
      expect(e.xpGained, 0);
      expect(e.leveledUp, isFalse);
      expect(e.newlyEarned, <String>['ok']);
    });
  });

  group('ServerProgressStore', () {
    test('read is empty before any write', () async {
      final ServerProgressStore store = await makeStore();
      final ServerProgressSnapshot snap = store.read();
      expect(snap.xp, 0);
      expect(snap.level, 1);
      expect(snap.earnedBadgeCodes, isEmpty);
    });

    test('adoptFromRead persists xp/level/badges', () async {
      final ServerProgressStore store = await makeStore();
      await store.adoptFromRead(
        xp: 620,
        level: 3,
        earnedBadgeCodes: <String>['first_win'],
      );
      final ServerProgressSnapshot snap = store.read();
      expect(snap.xp, 620);
      expect(snap.level, 3);
      expect(snap.earnedBadgeCodes, <String>['first_win']);
    });

    test('level progress math tracks the 250-XP curve', () async {
      final ServerProgressStore store = await makeStore();
      await store.adoptFromRead(xp: 620, level: 3, earnedBadgeCodes: const []);
      final ServerProgressSnapshot snap = store.read();
      // 620 = 2*250 + 120 → 120 into level 3, 130 to go.
      expect(snap.xpIntoLevel, 120);
      expect(snap.xpToNextLevel, 130);
      expect(snap.levelProgress, closeTo(0.48, 0.001));
    });

    test('clear wipes the snapshot', () async {
      final ServerProgressStore store = await makeStore();
      await store.adoptFromRead(
        xp: 100,
        level: 1,
        earnedBadgeCodes: <String>['first_win'],
      );
      await store.clear();
      final ServerProgressSnapshot snap = store.read();
      expect(snap.xp, 0);
      expect(snap.earnedBadgeCodes, isEmpty);
    });
  });
}
