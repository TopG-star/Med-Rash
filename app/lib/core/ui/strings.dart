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

  // Mode-selection home (Slice 2a front door)
  static const String modeSelectionIntro =
      'Pick how you want to play. Live for hosted sessions, Ranked for the leaderboard, Learn for unlimited practice.';
  static const String modeLiveLabel = 'Live';
  static const String modeLiveDescription =
      'Join a session in progress with a code or a QR scan.';
  static const String modeRankedLabel = 'Ranked';
  static const String modeRankedDescription =
      'One-shot attempts that count toward your career points and the world rank.';
  static const String modeLearnLabel = 'Learn';
  static const String modeLearnDescription =
      'Repeat any quiz as many times as you like — no points, no pressure.';
  static const String continueLastSessionTitle = 'Continue last session';
  static const String continueLastSessionCta = 'Resume';
  static const String exploreCta = 'Browse all content';

  // Explore (formerly Home feed)
  static const String exploreTitle = 'Explore';
  static const String exploreIntro =
      'Pick a topic and keep it under three minutes.';

  // Live tab
  static const String liveTitle = 'Live';
  static const String liveIntro =
      'Enter the session code your host announced, or scan the QR they shared.';
  static const String liveEnterCodeTitle = 'Enter session code';
  static const String liveEnterCodeHelper =
      'Four letters or digits, case-insensitive.';
  static const String liveEnterCodeLabel = 'Session code';
  static const String liveJoinCta = 'Join session';
  static const String liveScanQrTitle = 'Scan QR';
  static const String liveScanQrHelper =
      'Open the camera and point it at the QR your host displayed.';
  static const String liveScanQrCta = 'Open camera';
  static const String liveScanQrInstruction =
      'Centre the QR inside the frame. We\'ll take it from there.';
  static const String liveScanQrCancel = 'Type the code instead';
  static const String liveScanQrUnrecognised =
      'That QR doesn\'t look like a MedRash session. Try again.';
  static const String liveScanQrPermissionDenied =
      'Camera access was denied. Allow it in your browser or device settings, then retry.';
  static const String liveScanQrUnsupported =
      'This device can\'t open the camera. Use the code field instead.';
  static const String liveScanQrGenericError =
      'We couldn\'t start the camera. Use the code field instead.';

  // Ranked tab
  static const String rankedTitle = 'Ranked';
  static const String rankedIntro =
      'Each quiz gives you one ranked attempt. Score counts toward your career points.';
  static const String rankedTierGold = 'Gold';
  static const String rankedTierSilver = 'Silver';
  static const String rankedTierBronze = 'Bronze';

  // Learn tab
  static const String learnTitle = 'Learn';
  static const String learnIntro =
      'Practice anything as many times as you like. No points awarded.';

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
