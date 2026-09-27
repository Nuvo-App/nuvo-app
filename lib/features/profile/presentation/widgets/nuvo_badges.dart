import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_geometry.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/nuvo_entrance.dart';
import '../../../../core/widgets/nuvo_motion.dart';
import '../../../../core/widgets/nuvo_progress_bar.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../data/progression_models.dart';

/// Server `icon_key` → glyph. The server stores a stable identifier; the
/// mapping lives here so achievement art stays inside Nuvo's icon language.
/// `num_*` keys render as numerals, not icons.
IconData nuvoBadgeIconFor(String? iconKey) {
  switch (iconKey) {
    // Racing
    case 'arrow_forward':
      return Icons.east_rounded;
    case 'flag':
    case 'flags_5':
    case 'flags_stack':
      return Icons.flag_rounded;
    case 'flag_plus':
      return Icons.flag_circle_rounded;
    case 'flag_golf':
    case 'flag_golf_10':
      return Icons.golf_course_rounded;
    // Winning
    case 'trophy_1':
    case 'trophy_3':
    case 'trophy_5':
    case 'trophy_10':
    case 'trophy_25':
      return Icons.emoji_events_rounded;
    case 'crown':
    case 'crown_line':
      return Icons.workspace_premium_rounded;
    // Performance
    case 'spark_up':
    case 'spark':
      return Icons.auto_awesome_rounded;
    case 'chart_up':
      return Icons.trending_up_rounded;
    case 'arrow_curve':
      return Icons.u_turn_left_rounded;
    // Social
    case 'people':
    case 'people_flag':
      return Icons.groups_rounded;
    case 'crossed_flags':
      return Icons.sports_rounded;
    // Variety
    case 'tiles_4':
      return Icons.grid_view_rounded;
    case 'compass':
      return Icons.explore_rounded;
    // Motion
    case 'motion_figure':
    case 'motion_10':
      return Icons.directions_run_rounded;
    case 'motion_bolt':
      return Icons.bolt_rounded;
    // Proof / format
    case 'camera':
      return Icons.photo_camera_rounded;
    case 'camera_check':
      return Icons.photo_camera_back_rounded;
    case 'stopwatch':
    case 'stopwatch_bolt':
      return Icons.timer_rounded;
    // Category families
    case 'book':
      return Icons.menu_book_rounded;
    case 'books_stack':
      return Icons.auto_stories_rounded;
    case 'paper_grade':
      return Icons.school_rounded;
    case 'cap_grad':
      return Icons.school_outlined;
    // Capability ladder
    case 'slot':
      return Icons.dashboard_customize_rounded;
    case 'accent':
      return Icons.palette_rounded;
    case 'reaction':
      return Icons.add_reaction_rounded;
    case 'frame':
      return Icons.account_box_rounded;
    case 'blueprint':
      return Icons.architecture_rounded;
    default:
      return Icons.emoji_events_rounded;
  }
}

/// `num_5` / `num_10` / `num_25` / `num_50` / `num_100` render as numerals.
String? nuvoBadgeNumeralFor(String? iconKey) {
  if (iconKey == null || !iconKey.startsWith('num_')) return null;
  return iconKey.substring(4);
}

/// One achievement badge, in the Nuvo physical language — a thick-outlined
/// squircle with a hard offset shadow. Earned badges carry a flat accent
/// (blue standard, gold milestone); locked badges are muted and quiet.
/// The same silhouette renders on Profile, the collection, Crew person
/// sheets, and the unlock moment.
class NuvoAchievementBadge extends StatelessWidget {
  const NuvoAchievementBadge({
    super.key,
    required this.badge,
    this.size = 56,
  });

  final NuvoBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final radius = size * 0.30;
    final numeral = nuvoBadgeNumeralFor(badge.iconKey);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: badge.unlocked
            ? (badge.isMilestone ? NuvoColors.gold : NuvoColors.blue)
            : c.panelLight,
        border: Border.all(
          color: badge.unlocked ? c.inkShadow : c.border,
          width: 2.5,
        ),
        boxShadow: badge.unlocked
            ? [
                BoxShadow(
                  color: c.inkShadow,
                  offset: const Offset(3, 3),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: Center(
        child: badge.unlocked
            ? (numeral != null
                ? Text(
                    numeral,
                    style: AppTextStyles.displaySmall.copyWith(
                      color: NuvoColors.white,
                      fontSize: size * 0.34,
                      height: 1,
                    ),
                  )
                : Icon(
                    nuvoBadgeIconFor(badge.iconKey),
                    size: size * 0.44,
                    color: NuvoColors.white,
                  ))
            : Icon(
                Icons.lock_outline_rounded,
                size: size * 0.40,
                color: c.inkDim,
              ),
      ),
    );
  }
}

/// Back-compat name used by the badges screen and level-up dialog.
class NuvoBadgeDisc extends StatelessWidget {
  const NuvoBadgeDisc({
    super.key,
    required this.badge,
    this.size = 56,
    this.showRequirement = false,
  });

  final NuvoBadge badge;
  final double size;
  final bool showRequirement;

  @override
  Widget build(BuildContext context) {
    final badge = NuvoAchievementBadge(badge: this.badge, size: size);
    if (!showRequirement) return badge;
    final c = context.themeColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(height: 6),
        Text(
          this.badge.unlocked
              ? 'EARNED'
              : this.badge.requiredLevel > 0
                  ? 'LVL ${this.badge.requiredLevel}'
                  : 'LOCKED',
          style: AppTextStyles.labelUppercase(
            9,
            color: this.badge.unlocked ? c.inkSubtle : c.inkDim,
          ).copyWith(color: this.badge.unlocked ? c.inkSubtle : c.inkDim),
        ),
      ],
    );
  }
}

/// Compact badge for Crew/person surfaces — the same silhouette at a small
/// size, driven by the public identity payload (no full NuvoBadge needed).
class NuvoMiniBadge extends StatelessWidget {
  const NuvoMiniBadge({super.key, required this.iconKey, this.size = 28});

  final String? iconKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final numeral = nuvoBadgeNumeralFor(iconKey);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.30),
        color: NuvoColors.blue,
        border: Border.all(color: c.inkShadow, width: 2),
        boxShadow: [
          BoxShadow(
            color: c.inkShadow,
            offset: const Offset(1.5, 1.5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Center(
        child: numeral != null
            ? Text(
                numeral,
                style: AppTextStyles.displaySmall.copyWith(
                  color: NuvoColors.white,
                  fontSize: size * 0.36,
                  height: 1,
                ),
              )
            : Icon(
                nuvoBadgeIconFor(iconKey),
                size: size * 0.46,
                color: NuvoColors.white,
              ),
      ),
    );
  }
}

/// Achievement tab taxonomy shared by the self collection and public
/// earned-only collections.
const nuvoAchievementTabs = <String, String>{
  'All': '',
  'Racing': 'racing',
  'Winning': 'winning',
  'Creating': 'creation',
  'Performance': 'performance',
  'Social': 'social',
  'Variety': 'variety',
  'Motion': 'motion',
  'Special': 'special',
};

const nuvoSpecialCategories = {'proof', 'category', 'level'};

/// The achievement grid — earned and locked tiles in the shared silhouette.
/// Used by the self collection (with locked progress) and public
/// collections (earned-only).
class NuvoBadgeGrid extends StatelessWidget {
  const NuvoBadgeGrid({super.key, required this.badges, this.onTap});

  final List<NuvoBadge> badges;
  final void Function(NuvoBadge badge)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: NuvoSpacing.lg,
        crossAxisSpacing: NuvoSpacing.sm,
        childAspectRatio: 0.72,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) {
        final badge = badges[i];
        return PressableScale(
          onTap: onTap == null ? null : () => onTap!(badge),
          scale: 0.95,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: badge.unlocked ? 1 : 0.6,
                    child: NuvoAchievementBadge(badge: badge, size: 60),
                  ),
                  if (badge.featured)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NuvoColors.blue,
                          border: Border.all(color: c.page, width: 2),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: NuvoColors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                badge.name,
                style: AppTextStyles.labelSmall.copyWith(
                  color: badge.unlocked ? c.ink : c.inkDim,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),
              if (!badge.unlocked && badge.goalProgress > 0)
                SizedBox(
                  width: 52,
                  child: NuvoProgressBar(
                    value: badge.goalProgress,
                    height: 4,
                    color: NuvoColors.blue,
                    trackColor: c.track,
                  ),
                )
              else
                Text(
                  badge.unlocked ? 'Earned' : 'Locked',
                  style: AppTextStyles.labelUppercase(
                    9,
                    color: badge.unlocked ? c.inkSubtle : c.inkDim,
                  ).copyWith(
                    color: badge.unlocked ? c.inkSubtle : c.inkDim,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One achievement, large — what it is, what it asked for, where the viewer
/// stands. Read-only for public collections (no feature action, no locked
/// progress — the server never sends it for other people).
class NuvoAchievementDetailSheet extends StatelessWidget {
  const NuvoAchievementDetailSheet({
    super.key,
    required this.badge,
    this.onFeature,
  });

  final NuvoBadge badge;
  final VoidCallback? onFeature;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: c.inkShadow, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: c.inkShadow,
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: NuvoSpacing.lg),
          NuvoAchievementBadge(badge: badge, size: 72),
          const SizedBox(height: NuvoSpacing.md),
          Text(
            badge.name,
            style: AppTextStyles.headlineMedium.copyWith(color: c.ink),
            textAlign: TextAlign.center,
          ),
          if (badge.description != null) ...[
            const SizedBox(height: 6),
            Text(
              badge.description!,
              style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: NuvoSpacing.lg),
          if (badge.unlocked)
            Text(
              badge.unlockedAt != null && badge.unlockedAt != 'demo'
                  ? 'Earned ${badge.unlockedAt!.split('T').first}'
                  : 'Earned',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
              ),
            )
          else if (badge.threshold != null && badge.threshold! > 0)
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: NuvoProgressBar(
                        value: badge.goalProgress,
                        height: 8,
                        color: NuvoColors.blue,
                        trackColor: c.track,
                      ),
                    ),
                    const SizedBox(width: NuvoSpacing.sm),
                    Text(
                      '${badge.progressValue} / ${badge.threshold}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: c.inkSubtle,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (badge.threshold! - badge.progressValue == 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'One to go.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          if (onFeature != null) ...[
            const SizedBox(height: NuvoSpacing.lg),
            NuvoPressable(
              onTap: onFeature,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: badge.featured ? c.panelLight : NuvoColors.blue,
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  border: Border.all(color: c.inkShadow, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: c.inkShadow,
                      offset: const Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  badge.featured ? 'Unfeature' : 'Feature on Profile',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: badge.featured ? c.ink : NuvoColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ).nuvoEnter();
  }
}
