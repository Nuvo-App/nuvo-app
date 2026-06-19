class UserProfile {
  const UserProfile({
    required this.name,
    required this.username,
    this.memberId = '',
    this.id,
    this.email,
    this.passSlug,
    this.avatarUrl,
    this.privateProfile = false,
    this.onboardingComplete = false,
  });

  final String name;
  final String username;
  final String memberId;
  final String? id;
  final String? email;
  final String? passSlug;
  final String? avatarUrl;
  final bool privateProfile;
  final bool onboardingComplete;
}
