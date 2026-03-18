class LeaderboardItem {
  final int rank;
  final String name;
  final int points;
  final String email;
  final String? profileImageUrl;
  final String? profileImageBase64;
  final bool isOnline;
  final String activeFrame;

  const LeaderboardItem({
    required this.rank,
    required this.name,
    required this.points,
    required this.email,
    this.profileImageUrl,
    this.profileImageBase64,
    this.isOnline = false,
    this.activeFrame = 'none',
  });
}
