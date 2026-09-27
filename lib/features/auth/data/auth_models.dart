class AuthUser {
  final String id;
  final String email;
  final bool isDemo;
  final String? fullName;
  final String? username;
  final bool onboardingComplete;
  final bool hasMemberPass;
  final bool termsAccepted;
  final bool ageAttested;
  final bool motionTrainingConsent;
  final String? profilePhotoUrl;

  const AuthUser({
    required this.id,
    required this.email,
    this.isDemo = false,
    this.fullName,
    this.username,
    required this.onboardingComplete,
    required this.hasMemberPass,
    required this.termsAccepted,
    this.ageAttested = false,
    this.motionTrainingConsent = false,
    this.profilePhotoUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    isDemo: json['isDemo'] as bool? ?? false,
    fullName: json['fullName'] as String?,
    username: json['username'] as String?,
    onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    hasMemberPass: json['hasMemberPass'] as bool? ?? false,
    termsAccepted: json['termsAccepted'] as bool? ?? false,
    ageAttested: json['ageAttested'] as bool? ?? false,
    motionTrainingConsent: json['motionTrainingConsent'] as bool? ?? false,
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
    bool? ageAttested,
    bool? motionTrainingConsent,
    String? profilePhotoUrl,
    bool clearPhoto = false,
  }) => AuthUser(
    id: id,
    email: email,
    fullName: fullName ?? this.fullName,
    username: username ?? this.username,
    isDemo: isDemo,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    hasMemberPass: hasMemberPass ?? this.hasMemberPass,
    termsAccepted: termsAccepted ?? this.termsAccepted,
    ageAttested: ageAttested ?? this.ageAttested,
    motionTrainingConsent: motionTrainingConsent ?? this.motionTrainingConsent,
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

/// Fixture identity used when the store-review credential signs in with no
/// connectivity (e.g. a network that blocks workers.dev). Never produced by
/// a real server response — see AuthRepository.signInOfflineDemo.
AuthUser offlineDemoUser() => const AuthUser(
  id: 'offline-demo-user',
  email: 'team@getnuvo.net',
  isDemo: true,
  fullName: 'Nuvo Review',
  username: 'nuvoreview',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
  ageAttested: true,
);

/// Internal/demo eligibility — the ONE decision point for whether an account
/// sees the internal @getnuvo.net setup questionnaire. Evaluated on the
/// canonical backend-resolved account email ([AuthUser.email]), never on
/// provider callback payloads, so Apple private-relay addresses and provider
/// quirks cannot qualify an account that isn't actually internal.
///
/// Robust domain check: trims, takes the segment after the LAST '@',
/// lowercases, and compares for equality — so `a@getnuvo.net.evil.com`,
/// `a@fakegetnuvo.net`, and `getnuvo.net@other.com` are all correctly
/// rejected while `PERSON@GETNUVO.NET` is accepted.
bool isInternalNuvoAccount(AuthUser? user) {
  final email = user?.email.trim();
  if (email == null || email.isEmpty) return false;
  final at = email.lastIndexOf('@');
  if (at <= 0 || at >= email.length - 1) return false;
  return email.substring(at + 1).toLowerCase() == 'getnuvo.net';
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
