/// User-facing string registry for the MedRash app.
///
/// Centralised so that a future `flutter_localizations` / ARB migration can
/// swap this class for a generated `S.of(context)` accessor without touching
/// the call sites. Today every value is hard-coded English; nothing here is
/// runtime-formatted, so callers always read static fields.
class MedRashStrings {
  const MedRashStrings._();

  // App chrome
  static const String appTitle = 'MedRash';

  // Home
  static const String homeIntro =
      'Pick a topic and keep it under three minutes.';

  // Quiz runner
  static const String quizTitle = 'Quiz';
  static const String quizSubmit = 'Submit';
  static const String quizResumedBanner = 'Resuming where you left off.';
  static const String quizOfflineBanner =
      'Offline mode: your answers are saved on this device.';

  // Quiz result
  static const String resultHeadline = 'GREAT EFFORT!';
  static const String resultKnowledgeCheck = 'KNOWLEDGE CHECK';
  static const String resultBackToHome = 'Back To Home';
  static const String resultPendingTag = 'PENDING SYNC';
  static const String resultSavedTag = 'SAVED';
  static const String resultPendingMessage =
      'Saved on this device. We\u2019ll keep retrying in the background \u2014 your score is not lost.';
  static const String resultSyncedMessage = 'Saved and synced to MedRash.';
  static const String resultRetryLabel = 'Retry now';
  static const String resultRetryingLabel = 'Retrying\u2026';
  static const String resultNoAttempt = 'No completed attempt to display.';

  // Leaderboard
  static const String leaderboardTitle = 'World Rank';
  static const String leaderboardMonthly = 'Monthly';
  static const String leaderboardLast7Days = 'Last 7 Days';
  static const String leaderboardAllTime = 'All Time';
}
