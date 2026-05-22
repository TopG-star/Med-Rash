import 'dart:convert';

/// Snapshot of a participant's local identity captured at "soft" sign-out so
/// the next visit to `/join` can offer a one-tap "Continue as @nickname"
/// instead of forcing them through the signup form (and minting a new
/// server-side user row that orphans their old rank).
///
/// Never written on "Hand to someone else" sign-out — that path is the
/// privacy-correct break.
class IdentitySnapshot {
  const IdentitySnapshot({
    required this.participantId,
    required this.deviceInstallId,
    required this.fullName,
    required this.nickname,
    required this.facility,
    required this.specialty,
    required this.totalPoints,
    required this.rank,
    required this.signedOutAt,
  });

  final String participantId;
  final String deviceInstallId;
  final String fullName;
  final String nickname;
  final String facility;
  final String specialty;
  final int totalPoints;
  final int rank;
  final DateTime signedOutAt;

  /// Snapshots older than this are treated as missing — protects shared
  /// devices from auto-resuming a stranger's identity weeks later.
  static const Duration maxAge = Duration(days: 30);

  bool get isExpired => DateTime.now().difference(signedOutAt) > maxAge;

  Map<String, Object?> toJson() => <String, Object?>{
        'participantId': participantId,
        'deviceInstallId': deviceInstallId,
        'fullName': fullName,
        'nickname': nickname,
        'facility': facility,
        'specialty': specialty,
        'totalPoints': totalPoints,
        'rank': rank,
        'signedOutAt': signedOutAt.toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  static IdentitySnapshot? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final String? participantId = decoded['participantId'] as String?;
      final String? deviceInstallId = decoded['deviceInstallId'] as String?;
      final String? fullName = decoded['fullName'] as String?;
      final String? signedOutAtRaw = decoded['signedOutAt'] as String?;
      if (participantId == null ||
          deviceInstallId == null ||
          fullName == null ||
          signedOutAtRaw == null) {
        return null;
      }
      final DateTime? signedOutAt = DateTime.tryParse(signedOutAtRaw);
      if (signedOutAt == null) {
        return null;
      }
      return IdentitySnapshot(
        participantId: participantId,
        deviceInstallId: deviceInstallId,
        fullName: fullName,
        nickname: (decoded['nickname'] as String?) ?? '',
        facility: (decoded['facility'] as String?) ?? '',
        specialty: (decoded['specialty'] as String?) ?? 'Doctor',
        totalPoints: (decoded['totalPoints'] as num?)?.toInt() ?? 0,
        rank: (decoded['rank'] as num?)?.toInt() ?? 0,
        signedOutAt: signedOutAt,
      );
    } catch (_) {
      return null;
    }
  }
}
