class IdentitySpine {
  const IdentitySpine({
    required this.deviceInstallId,
    required this.participantId,
    required this.hasBoundProfile,
  });

  final String deviceInstallId;
  final String participantId;
  final bool hasBoundProfile;

  IdentitySpine copyWith({
    String? deviceInstallId,
    String? participantId,
    bool? hasBoundProfile,
  }) {
    return IdentitySpine(
      deviceInstallId: deviceInstallId ?? this.deviceInstallId,
      participantId: participantId ?? this.participantId,
      hasBoundProfile: hasBoundProfile ?? this.hasBoundProfile,
    );
  }
}
