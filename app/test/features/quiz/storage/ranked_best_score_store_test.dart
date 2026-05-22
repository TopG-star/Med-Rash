import 'package:flutter_test/flutter_test.dart';
import 'package:medrash_app/core/events/medrash_events.dart';
import 'package:medrash_app/core/infra/event_bus.dart';
import 'package:medrash_app/features/quiz/storage/ranked_best_score_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('rankedTierFromPercent', () {
    test('thresholds: gold >=90, silver 70-89, bronze 50-69, none <50', () {
      expect(rankedTierFromPercent(100), RankedTier.gold);
      expect(rankedTierFromPercent(90), RankedTier.gold);
      expect(rankedTierFromPercent(89), RankedTier.silver);
      expect(rankedTierFromPercent(70), RankedTier.silver);
      expect(rankedTierFromPercent(69), RankedTier.bronze);
      expect(rankedTierFromPercent(50), RankedTier.bronze);
      expect(rankedTierFromPercent(49), RankedTier.none);
      expect(rankedTierFromPercent(0), RankedTier.none);
    });
  });

  group('RankedBestScoreStore', () {
    test('recordRanked persists percent and bestPercentFor reads it', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RankedBestScoreStore store = RankedBestScoreStore(prefs);

      final bool changed = await store.recordRanked('quiz-a', 8, 10);

      expect(changed, isTrue);
      expect(store.bestPercentFor('quiz-a'), 80);
    });

    test('recordRanked only updates when the new percent is higher', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RankedBestScoreStore store = RankedBestScoreStore(prefs);
      await store.recordRanked('quiz-a', 9, 10); // 90

      final bool lower = await store.recordRanked('quiz-a', 5, 10); // 50

      expect(lower, isFalse);
      expect(store.bestPercentFor('quiz-a'), 90);
    });

    test('recordRanked ignores empty quizId and zero totals', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RankedBestScoreStore store = RankedBestScoreStore(prefs);

      expect(await store.recordRanked('', 5, 10), isFalse);
      expect(await store.recordRanked('quiz-a', 5, 0), isFalse);
      expect(store.snapshot(), isEmpty);
    });

    test('AttemptSubmittedEvent records ranked attempts and ignores learning', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final EventBus bus = EventBus();
      final RankedBestScoreStore store = RankedBestScoreStore(prefs, eventBus: bus);

      bus.emit(const AttemptSubmittedEvent(
        quizId: 'quiz-a',
        mode: 'learning',
        origin: 'open_access',
        score: 10,
        totalQuestions: 10,
      ));
      bus.emit(const AttemptSubmittedEvent(
        quizId: 'quiz-b',
        mode: 'ranked',
        origin: 'qr_session',
        score: 7,
        totalQuestions: 10,
      ));

      // Allow the microtask queue to drain so async listeners fire.
      await Future<void>.delayed(Duration.zero);

      expect(store.bestPercentFor('quiz-a'), isNull);
      expect(store.bestPercentFor('quiz-b'), 70);

      await store.dispose();
    });

    test('IdentityResetEvent clears persisted scores', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final EventBus bus = EventBus();
      final RankedBestScoreStore store = RankedBestScoreStore(prefs, eventBus: bus);
      await store.recordRanked('quiz-a', 9, 10);
      expect(store.bestPercentFor('quiz-a'), 90);

      bus.emit(const IdentityResetEvent(keptDeviceId: false));
      await Future<void>.delayed(Duration.zero);

      expect(store.bestPercentFor('quiz-a'), isNull);
      expect(store.snapshot(), isEmpty);

      await store.dispose();
    });
  });
}
