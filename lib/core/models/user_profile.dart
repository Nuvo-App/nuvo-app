class UserProfile {
  final String id;
  final String name;
  final String username;
  final String phone;
  final int wins;
  final int losses;
  final int streakDays;
  final List<String> badges;

  const UserProfile({
    required this.id,
    required this.name,
    required this.username,
    required this.phone,
    this.wins = 0,
    this.losses = 0,
    this.streakDays = 0,
    this.badges = const [],
  });

  String get avatarInitials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  UserProfile copyWith({
    String? name,
    String? username,
    int? wins,
    int? losses,
    int? streakDays,
    List<String>? badges,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      username: username ?? this.username,
      phone: phone,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      streakDays: streakDays ?? this.streakDays,
      badges: badges ?? this.badges,
    );
  }
}
