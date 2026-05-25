/// Snapshot of the current participant's identity used across the app.
///
/// Two separate strings intentionally play two different roles:
///
/// * [fullName] is the participant's real name. Use it in confirmations,
///   onboarding greetings, and anywhere we want to acknowledge the human
///   behind the device. It is never shown on the public leaderboard.
/// * [nickname] is the public-facing handle shown on the leaderboard, podium
///   row, and result share cards. Treat it as a stable @-handle: prefix it
///   with `@` in chrome and avoid mixing it with [fullName] in the same
///   sentence.
class UserProfile {
  const UserProfile({
    required this.fullName,
    required this.nickname,
    required this.facility,
    required this.specialty,
    required this.totalPoints,
    required this.rank,
    this.email,
  });

  /// The participant's real name. Confidential outside of confirmations.
  final String fullName;

  /// Public leaderboard handle. Always render with an `@` prefix in chrome.
  final String nickname;
  final String facility;
  final String specialty;
  final int totalPoints;
  final int rank;

  /// Optional recovery email captured in slice 6a. Used by slice 6b to rebind
  /// this `app.users` row to a new device after a reinstall / phone switch.
  /// Never displayed in public UI.
  final String? email;
}