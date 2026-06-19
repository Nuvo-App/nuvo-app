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
  });

  final UserProfile profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3307152B),
            blurRadius: 26,
            offset: Offset(0, 16),
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
                color: NuvoColors.blue.withValues(alpha: 0.18),
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
                      color: NuvoColors.white,
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
                      color: NuvoColors.blue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.white,
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
                  color: NuvoColors.white,
                  fontSize: compact ? 22 : 28,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                profile.username,
                style: AppTextStyles.labelLarge.copyWith(
                  color: NuvoColors.softBlue,
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
                  color: NuvoColors.white.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: NuvoColors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  'ID: ${profile.memberId}',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: NuvoColors.white,
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
