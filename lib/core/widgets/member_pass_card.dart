import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/models/user_profile.dart';
import '../constants/asset_paths.dart';
import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

class MemberPassCard extends StatelessWidget {
  const MemberPassCard({
    super.key,
    required this.profile,
    this.compact = false,
    this.dark = false,
  });

  final UserProfile profile;
  final bool compact;

  /// Solid-navy "pass in your pocket" treatment, matching the Crew screen's
  /// member pass moment. When false, keeps the original light card used in
  /// onboarding.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (dark) return _buildDark(context);

    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(
          compact ? NuvoRadii.lg : NuvoRadii.hero,
        ),
        border: NuvoBorders.quiet,
        boxShadow: compact ? null : AppShadows.heroShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                AssetPaths.nuvoLogo,
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              Text(
                'NUVO PASS',
                style: AppTextStyles.brandLabel.copyWith(
                  color: NuvoColors.navy,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: NuvoColors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: NuvoColors.blue.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  'ACTIVE',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 30),
          Text(
            profile.name,
            style: AppTextStyles.headlineLarge.copyWith(
              color: NuvoColors.navy,
              fontSize: compact ? 22 : 28,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.username,
            style: AppTextStyles.labelLarge.copyWith(color: NuvoColors.muted),
          ),
          SizedBox(height: compact ? 20 : 28),
          Center(
            child: _QrFrame(
              value: 'https://nuvo.app/pass/${profile.memberId}',
              size: compact ? 136 : 176,
            ),
          ),
          SizedBox(height: compact ? 18 : 26),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: NuvoColors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: NuvoColors.border),
            ),
            child: Text(
              'ID: ${profile.memberId}',
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDark(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 22),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(
          compact ? NuvoRadii.lg : NuvoRadii.hero,
        ),
        border: Border.all(color: NuvoColors.navy2, width: 1.2),
        boxShadow: AppShadows.heroShadow,
      ),
      child: Column(
        children: [
          Text(
            'NUVO PASS',
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 10 : 18),
          _QrFrame(
            value: 'https://nuvo.app/pass/${profile.memberId}',
            size: compact ? 88 : 128,
          ),
          SizedBox(height: compact ? 10 : 18),
          Text(
            profile.name,
            style: AppTextStyles.titleLarge.copyWith(
              color: Colors.white,
              fontSize: compact ? 16 : 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            profile.username,
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'ID · ${profile.memberId}',
              style: AppTextStyles.labelSmall.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrFrame extends StatelessWidget {
  const _QrFrame({required this.value, required this.size});

  final String value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      child: QrImageView(
        data: value,
        size: size,
        backgroundColor: NuvoColors.white,
      ),
    );
  }
}
