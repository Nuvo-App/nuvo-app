import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/models/user_profile.dart';
import '../constants/asset_paths.dart';
import '../theme/app_colors.dart';
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [NuvoColors.white, NuvoColors.inkWash, NuvoColors.icyBlue],
        ),
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180A1A33),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -58,
            top: -38,
            child: Transform.rotate(
              angle: -0.55,
              child: Container(
                width: 180,
                height: 70,
                color: NuvoColors.blue.withValues(alpha: 0.12),
              ),
            ),
          ),
          Column(
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
                style: AppTextStyles.labelLarge.copyWith(
                  color: NuvoColors.muted,
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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
        ],
      ),
    );
  }

  Widget _buildDark(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 20 : 24),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(compact ? 22 : 26),
      ),
      child: Column(
        children: [
          Text(
            'NUVO PASS',
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
              letterSpacing: 2.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 16 : 20),
          _QrFrame(
            value: 'https://nuvo.app/pass/${profile.memberId}',
            size: compact ? 112 : 136,
          ),
          SizedBox(height: compact ? 16 : 20),
          Text(
            profile.name,
            style: AppTextStyles.titleLarge.copyWith(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            profile.username,
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'ID · ${profile.memberId}',
              style: AppTextStyles.labelMedium.copyWith(
                color: Colors.white,
                letterSpacing: 0.3,
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
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size + 22,
          height: size + 22,
          decoration: BoxDecoration(
            color: NuvoColors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: NuvoColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120A1A33),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
        ),
        QrImageView(data: value, size: size, backgroundColor: NuvoColors.white),
        for (final alignment in const [
          Alignment.topLeft,
          Alignment.topRight,
          Alignment.bottomLeft,
          Alignment.bottomRight,
        ])
          Align(
            alignment: alignment,
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border(
                  top: alignment.y < 0
                      ? const BorderSide(color: NuvoColors.blue, width: 4)
                      : BorderSide.none,
                  bottom: alignment.y > 0
                      ? const BorderSide(color: NuvoColors.blue, width: 4)
                      : BorderSide.none,
                  left: alignment.x < 0
                      ? const BorderSide(color: NuvoColors.blue, width: 4)
                      : BorderSide.none,
                  right: alignment.x > 0
                      ? const BorderSide(color: NuvoColors.blue, width: 4)
                      : BorderSide.none,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
