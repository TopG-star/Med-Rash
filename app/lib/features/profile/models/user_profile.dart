class UserProfile {
  const UserProfile({
    required this.fullName,
    required this.nickname,
    required this.facility,
    required this.specialty,
    required this.totalPoints,
    required this.rank,
  });

  final String fullName;
  final String nickname;
  final String facility;
  final String specialty;
  final int totalPoints;
  final int rank;
}