import 'package:flutter/material.dart';

import '../../../../core/v13/v13.dart';
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

/// The accent an earned badge carries — the achievement's family, not
/// decoration. The same v13 palette mapping [v13BadgeAccent] uses:
/// winning & milestones = gold, racing = coral, performance = mint,
/// creation & motion = lilac, social & variety = sun, everything else =
/// sky. Locked badges never take color — they stay dashed regardless of
/// family.
Color nuvoBadgeAccent(NuvoBadge badge) {
  if (badge.isMilestone) return V13.gold;
  return switch (badge.category) {
    'winning' => V13.gold,
    'racing' => V13.coral,
    'performance' => V13.mint,
    'creation' || 'motion' => V13.lilac,
    'social' || 'variety' => V13.sun,
    _ => V13.sky,
  };
}

/// One achievement badge in the v13 language — an icon tile (radius 12–16)
/// with a navy glyph. Earned badges fill with their family accent (see
/// [nuvoBadgeAccent]) and carry the navy outline + hard shadow; locked
/// badges are white with a dashed muted outline and a lock glyph.
/// The same silhouette renders on Profile, the collection, Crew person
/// sheets, onboarding and the earn moments.
class NuvoAchievementBadge extends StatelessWidget {
  const NuvoAchievementBadge({super.key, required this.badge, this.size = 56});

  final NuvoBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = (size * 0.28).clamp(12.0, V13.radiusTileLg).toDouble();
    final numeral = nuvoBadgeNumeralFor(badge.iconKey);
    final Widget glyph = badge.unlocked
        ? (numeral != null
              ? Text(
                  numeral,
                  style: V13.number.copyWith(
                    fontSize: size * 0.34,
                    color: V13.navy,
                  ),
                )
              : Icon(
                  nuvoBadgeIconFor(badge.iconKey),
                  size: size * 0.44,
                  color: V13.navy,
                ))
        : Icon(Icons.lock_outline_rounded, size: size * 0.40, color: V13.muted);
    if (!badge.unlocked) {
      return _DashedBadgeOutline(
        radius: radius,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: V13.card,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Center(child: glyph),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: nuvoBadgeAccent(badge),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: V13.navy, width: V13.outline),
        boxShadow: V13.shadow3,
      ),
      child: Center(child: glyph),
    );
  }
}

/// The v13 locked badge edge — a dashed muted outline, same look as the
/// locked tiles on the badges page.
class _DashedBadgeOutline extends StatelessWidget {
  const _DashedBadgeOutline({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBadgePainter(radius: radius),
      child: child,
    );
  }
}

class _DashedBadgePainter extends CustomPainter {
  const _DashedBadgePainter({required this.radius});

  final double radius;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = V13.muted
      ..style = PaintingStyle.stroke
      ..strokeWidth = V13.outline;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(V13.outline / 2);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBadgePainter old) => old.radius != radius;
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
          style: V13.label.copyWith(fontSize: 9),
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
    final numeral = nuvoBadgeNumeralFor(iconKey);
    final radius = (size * 0.30).clamp(10.0, V13.radiusTileLg).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: V13.blue,
        border: Border.all(color: V13.navy, width: V13.outline),
        boxShadow: V13.hardShadow(x: 1.5, y: 1.5),
      ),
      child: Center(
        child: numeral != null
            ? Text(
                numeral,
                style: V13.number.copyWith(
                  color: V13.white,
                  fontSize: size * 0.36,
                ),
              )
            : Icon(
                nuvoBadgeIconFor(iconKey),
                size: size * 0.46,
                color: V13.white,
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
    // Tiles size to their content (badge + name + status line) and a Wrap
    // lays them three across. The badge grows with its column so wide
    // phones aren't a sparse field of small marks, and narrow ones stay
    // comfortable.
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
        const colGap = V13.gapSm;
        final tileWidth =
            ((constraints.maxWidth - colGap * (columns - 1)) / columns)
                .floorToDouble();
        final statusHeight = MediaQuery.textScalerOf(context).scale(12);
        final badgeSize = (tileWidth * 0.58).clamp(52.0, 76.0).toDouble();
        return Wrap(
          spacing: colGap,
          runSpacing: _rowGap,
          children: [
            for (final badge in badges)
              SizedBox(
                width: tileWidth,
                child: _tile(context, badge, statusHeight, badgeSize),
              ),
          ],
        );
      },
    );
  }

  /// Visible gap between one row's status line and the next row's badge.
  static const double _rowGap = 34;

  Widget _tile(
    BuildContext context,
    NuvoBadge badge,
    double statusHeight,
    double badgeSize,
  ) {
    return V13Pressable(
      onTap: onTap == null ? null : () => onTap!(badge),
      pressDepth: 2,
      semanticLabel: badge.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: badge.unlocked ? 1 : 0.7,
                child: NuvoAchievementBadge(badge: badge, size: badgeSize),
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
                      color: V13.blue,
                      border: Border.all(color: V13.bg, width: 2),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: V13.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Long names scale down to fit the tile instead of ellipsizing.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              badge.name,
              style: V13.caption.copyWith(
                color: badge.unlocked ? V13.navy : V13.muted,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: statusHeight,
            child: Center(
              child: !badge.unlocked && badge.goalProgress > 0
                  ? SizedBox(
                      width: 52,
                      child: V13ProgressBar(
                        value: badge.goalProgress,
                        height: 5,
                      ),
                    )
                  : Text(
                      badge.unlocked ? 'Earned' : 'Locked',
                      style: V13.label.copyWith(fontSize: 9),
                    ),
            ),
          ),
        ],
      ),
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
    // Shell owns the sheet: surface, radius, drag handle, and dismissal.
    // Content never draws its own grabber — the SafeArea + scroll view keep
    // every CTA above the home indicator and reachable at max text scale.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          V13.pagePad,
          0,
          V13.pagePad,
          V13.gapXxl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: V13.gapSm),
            NuvoAchievementBadge(badge: badge, size: 72),
            const SizedBox(height: V13.gapLg),
            Text(
              badge.name,
              style: V13.sectionHead,
              textAlign: TextAlign.center,
            ),
            if (badge.description != null) ...[
              const SizedBox(height: 6),
              Text(
                badge.description!,
                style: V13.body.copyWith(color: V13.muted),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: V13.gapLg),
            if (badge.unlocked)
              Text(
                badge.unlockedAt != null && badge.unlockedAt != 'demo'
                    ? 'Earned ${badge.unlockedAt!.split('T').first}'
                    : 'Earned',
                style: V13.caption.copyWith(
                  color: V13.blue,
                  fontWeight: FontWeight.w800,
                ),
              )
            else if (badge.threshold != null && badge.threshold! > 0)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: V13ProgressBar(
                          value: badge.goalProgress,
                          height: 8,
                        ),
                      ),
                      const SizedBox(width: V13.gapSm),
                      Text(
                        '${badge.progressValue} / ${badge.threshold}',
                        style: V13.caption.copyWith(
                          color: V13.navy,
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
                        style: V13.caption.copyWith(
                          color: V13.blue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            if (onFeature != null) ...[
              const SizedBox(height: V13.gapLg),
              if (badge.featured)
                V13Button.secondary(
                  label: 'Remove from profile',
                  fullWidth: true,
                  onPressed: onFeature,
                )
              else
                V13Button.primary(
                  label: 'Show on profile',
                  fullWidth: true,
                  onPressed: onFeature,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
