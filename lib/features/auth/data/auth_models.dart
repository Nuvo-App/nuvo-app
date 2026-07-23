class AuthUser {
  final String id;
  final String email;
  final String? fullName;
  final String? username;
  final bool onboardingComplete;
  final bool hasMemberPass;
  final bool termsAccepted;
  final String? profilePhotoUrl;

  const AuthUser({
    required this.id,
    required this.email,
    this.fullName,
    this.username,
    required this.onboardingComplete,
    required this.hasMemberPass,
    required this.termsAccepted,
    this.profilePhotoUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['fullName'] as String?,
    username: json['username'] as String?,
    onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    hasMemberPass: json['hasMemberPass'] as bool? ?? false,
    termsAccepted: json['termsAccepted'] as bool? ?? false,
    profilePhotoUrl:
        (json['profilePhotoUrl'] ??
                json['profile_photo_url'] ??
                json['avatarUrl'] ??
                json['avatar_url'])
            as String?,
  );

  AuthUser copyWith({
    String? fullName,
    String? username,
    bool? onboardingComplete,
    bool? hasMemberPass,
    bool? termsAccepted,
    String? profilePhotoUrl,
    bool clearPhoto = false,
  }) => AuthUser(
    id: id,
    email: email,
    fullName: fullName ?? this.fullName,
    username: username ?? this.username,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    hasMemberPass: hasMemberPass ?? this.hasMemberPass,
    termsAccepted: termsAccepted ?? this.termsAccepted,
    profilePhotoUrl: clearPhoto
        ? null
        : (profilePhotoUrl ?? this.profilePhotoUrl),
  );

  String get avatarInitials {
    final src = fullName?.trim().isNotEmpty == true ? fullName! : email;
    final parts = src.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = src.trim();
    return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }
}

class PassInfo {
  final String memberId;
  final String passSlug;
  final String shareUrl;

  const PassInfo({
    required this.memberId,
    required this.passSlug,
    required this.shareUrl,
  });

  factory PassInfo.fromJson(Map<String, dynamic> json) => PassInfo(
    memberId: json['memberId'] as String,
    passSlug: json['passSlug'] as String,
    shareUrl: json['shareUrl'] as String,
  );
}

class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
  );
}
