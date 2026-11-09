import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/motion/motion.dart';
import '../../../core/network/api_base.dart';
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_copy.dart';
import '../flow/xp_table.dart';

/// What the level-up screen shows in its reward tiles. Real server values
/// when the grant call lands; the spec constants otherwise (offline never
/// strands the moment — the grant itself is idempotent and retried by
/// graduation).
class OnboardingReward {
  const OnboardingReward({
    required this.xp,
    required this.fromLevel,
    required this.toLevel,
    required this.badgeName,
    required this.streakDays,
    this.fromServer = false,
  });

  final int xp;
  final int fromLevel;
  final int toLevel;
  final String badgeName;
  final int streakDays;

  /// True when these numbers came from `POST /onboarding/complete`.
  final bool fromServer;

  /// Spec constants: +100 XP, Level 1 to 2, "Day One", day-1 streak.
  static const OnboardingReward fallback = OnboardingReward(
    xp: OnboardingXp.total,
    fromLevel: 1,
    toLevel: 2,
    badgeName: ObCopy.levelUpBadgeTile,
    streakDays: 1,
  );

  /// Parses the additive `reward` object of `POST /onboarding/complete`.
  /// Returns null when an old server sent none.
  static OnboardingReward? fromResponse(Map<String, dynamic> body) {
    final r = body['reward'];
    if (r is! Map) return null;
    final level = (r['level'] as num?)?.toInt();
    if (level == null) return null;
    final previous = (r['previousLevel'] as num?)?.toInt() ?? 1;
    final granted = (r['xpGranted'] as num?)?.toInt() ?? 0;
    // A repeat call (xpGranted 0) still celebrates the level the grant made.
    final from = granted > 0 ? previous : (level > 1 ? level - 1 : level);
    final badge = r['badge'];
    return OnboardingReward(
      xp: granted > 0 ? granted : OnboardingXp.total,
      fromLevel: from,
      toLevel: level,
      badgeName: badge is Map && badge['name'] is String
          ? badge['name'] as String
          : ObCopy.levelUpBadgeTile,
      streakDays: ((r['streakDays'] as num?)?.toInt() ?? 1).clamp(1, 9999),
      fromServer: true,
    );
  }

  String get xpTile => '+$xp XP';
  String get levelFromLabel => 'LEVEL $fromLevel';
  String get levelToLabel => 'LEVEL $toLevel';
  String get streakTile =>
      streakDays <= 1 ? ObCopy.levelUpStreakTile : '$streakDays day streak';
}

/// Calls the idempotent grant. The server write that flips the onboarding
/// flag is also this route, so the call is safe to repeat (graduation calls
/// it again through the auth controller — the XP never pays twice).
typedef OnboardingRewardFetcher = Future<OnboardingReward> Function();

final onboardingRewardFetcherProvider = Provider<OnboardingRewardFetcher>((
  ref,
) {
  return () async {
    try {
      final token = await ref.read(secureTokenStoreProvider).getAccessToken();
      if (token == null) return OnboardingReward.fallback;
      final res = await http
          .post(
            Uri.parse('$kNuvoApiBase/onboarding/complete'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{}),
          )
          .timeout(NuvoMotion.levelUpFetchTimeout);
      if (res.statusCode >= 400) return OnboardingReward.fallback;
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return OnboardingReward.fallback;
      return OnboardingReward.fromResponse(body) ?? OnboardingReward.fallback;
    } catch (_) {
      return OnboardingReward.fallback;
    }
  };
});

/// Loaded once when the level-up step mounts; never throws.
final onboardingRewardProvider = FutureProvider<OnboardingReward>(
  (ref) => ref.read(onboardingRewardFetcherProvider)(),
);
