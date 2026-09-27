import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_geometry.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/nuvo_button.dart';
import '../../../../core/widgets/nuvo_motion.dart';
import '../../data/progression_models.dart';
import 'nuvo_badges.dart';

/// The level-up moment — short, physical, once per level (the server keeps
/// last_seen_level so it never replays across restarts or devices).
Future<void> showLevelUpMoment(
  BuildContext context, {
  required int level,
  NuvoBadge? badge,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: context.themeColors.inkShadow.withValues(alpha: 0.5),
    builder: (ctx) {
      final c = ctx.themeColors;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.lg),
            border: Border.all(color: c.border, width: 2),
            boxShadow: AppShadows.hardOffset(
              c.inkShadow,
              offset: const Offset(6, 6),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LEVEL UP',
                style: AppTextStyles.labelUppercase(
                  12,
                  color: NuvoColors.blue,
                ).copyWith(color: NuvoColors.blue),
              ),
              const SizedBox(height: NuvoSpacing.sm),
              NuvoPop(
                trigger: level,
                intensity: 1.2,
                child: Text(
                  '$level',
                  style: AppTextStyles.number(
                    64,
                    color: c.ink,
                    weight: FontWeight.w900,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(height: NuvoSpacing.md),
                Text(
                  'UNLOCKED',
                  style: AppTextStyles.labelUppercase(
                    10,
                    color: c.inkSubtle,
                  ).copyWith(color: c.inkSubtle),
                ),
                const SizedBox(height: NuvoSpacing.sm),
                NuvoBadgeDisc(badge: badge, size: 64),
                const SizedBox(height: NuvoSpacing.sm),
                Text(
                  badge.name,
                  style: AppTextStyles.titleMedium.copyWith(color: c.ink),
                  textAlign: TextAlign.center,
                ),
                if (badge.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    badge.description!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: c.inkMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
              const SizedBox(height: NuvoSpacing.xl),
              NuvoPrimaryButton(
                label: 'Keep racing',
                expand: true,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}
