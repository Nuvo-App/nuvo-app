import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/widgets/nuvo_badges.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/v13/submit_proof_entry.dart';

import 'arena_v13_data.dart';
import 'arena_v13_empty.dart';

/// "Hey [first name]" + the streak/level line, notification bell with its
/// coral unread badge, and the avatar inside the XP ring.
class ArenaHeader extends StatelessWidget {
  const ArenaHeader({
    super.key,
    required this.firstName,
    this.streakDays,
    this.level,
    this.levelLoading = false,
    this.xpProgress = 0,
    this.photoUrl,
    this.unreadCount = 0,
    this.dayOne = false,
    required this.onBellTap,
    required this.onAvatarTap,
  });

  final String firstName;

  /// Null → the streak clause is hidden (older Workers don't emit it).
  final int? streakDays;
  final int? level;

  /// True while the first progression fetch is in flight — the sub-line
  /// skeletonizes rather than flashing a stale line.
  final bool levelLoading;
  final double xpProgress;
  final String? photoUrl;
  final int unreadCount;

  /// Brand-new account — the level line ends with "Day 1".
  final bool dayOne;
  final VoidCallback onBellTap;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final sub = <String>[
      if ((streakDays ?? 0) > 0) '$streakDays day streak',
      if (level != null) 'Level $level',
      if (dayOne && level != null) 'Day 1',
    ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hey $firstName',
                style: V13.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: V13.gapXs),
              if (levelLoading)
                const V13Skeleton.line(width: 140)
              else if (sub.isNotEmpty)
                Row(
                  children: [
                    if ((streakDays ?? 0) > 0) ...[
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 16,
                        color: V13.coral,
                      ),
                      const SizedBox(width: V13.gapXs - 1),
                    ],
                    Flexible(
                      child: Text(
                        sub,
                        style: V13.caption.copyWith(
                          color: V13.navy,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(width: V13.gapSm),
        V13IconButton(
          icon: Icons.notifications_none_rounded,
          badgeCount: unreadCount,
          onTap: onBellTap,
          semanticLabel: 'Notifications',
        ),
        const SizedBox(width: V13.gapSm),
        V13XpRing(
          progress: xpProgress,
          photoUrl: photoUrl,
          name: firstName,
          size: 46,
          emptyFill: V13.sky,
          trackColor: (photoUrl ?? '').isEmpty
              ? V13.blue.withValues(alpha: 0.2)
              : V13.divider,
          onTap: onAvatarTap,
          semanticLabel: 'Your profile',
        ),
      ],
    );
  }
}

/// "[Name] passed you" / "2 to pass Alex" — the one actionable nudge under
/// the swiper. The action is always the shared Submit proof entry.
class ArenaNudgeRow extends ConsumerWidget {
  const ArenaNudgeRow({super.key, required this.nudge});

  final ArenaNudge nudge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return V13Card(
      padding: const EdgeInsets.all(V13.gapMd),
      child: Row(
        children: [
          V13Face(
            photoUrl: nudge.actorPhotoUrl,
            size: 40,
            name: nudge.actorId,
            onTap: nudge.actorId == null
                ? null
                : () => openPerson(context, ref, nudge.actorId!),
          ),
          const SizedBox(width: V13.gapMd - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nudge.headline,
                  style: V13.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  nudge.subline,
                  style: V13.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: V13.gapSm),
          V13Button.secondary(
            label: 'Take it back',
            size: V13ButtonSize.small,
            onPressed: () async {
              await openSubmitProof(context, ref, nudge.race);
              if (!context.mounted) return;
              ref.read(raceControllerProvider.notifier).markStale();
            },
          ),
        ],
      ),
    );
  }
}

/// The 18-week proof heat map with its count line, active-days line, and
/// legend. Owns its own loading / empty / error + retry so a slow fetch
/// never blanks the sections around it.
class ArenaActivitySection extends StatelessWidget {
  const ArenaActivitySection({
    super.key,
    required this.days,
    required this.status,
    required this.onRetry,
  });

  /// Normalized counts keyed by local day — ignored unless [status] is data.
  final Map<DateTime, int> days;
  final AsyncValue<void> status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status.isLoading && !status.hasValue) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V13Skeleton.line(width: 150),
          SizedBox(height: V13.gapXs),
          V13Skeleton.line(width: 100),
          SizedBox(height: V13.gapMd),
          V13Skeleton.box(width: double.infinity, height: 92),
        ],
      );
    }
    if (status.hasError && !status.hasValue) {
      return ArenaSectionError(
        message: 'Couldn’t load activity',
        onRetry: onRetry,
      );
    }
    final proofs = arenaProofTotal(days);
    final active = arenaActiveDayCount(days);
    if (proofs == 0) return const ArenaActivityEmpty();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$proofs proofs · 18 weeks', style: V13.bodyStrong),
        Text('$active active days', style: V13.caption),
        const SizedBox(height: V13.gapMd),
        V13HeatMap(counts: days, weeks: 18, semanticLabel: 'Proof activity'),
      ],
    );
  }
}

/// "Achievements · [earned] of [total]" + four badge tiles — featured first,
/// then most recently earned, then locked achievements nearest to done.
class ArenaAchievementsSection extends StatelessWidget {
  const ArenaAchievementsSection({
    super.key,
    required this.progression,
    required this.tiles,
    required this.onOpenBadges,
  });

  final NuvoProgression progression;
  final List<NuvoBadge> tiles;
  final VoidCallback onOpenBadges;

  @override
  Widget build(BuildContext context) {
    if (progression.achievementsEarned == 0 &&
        tiles.isNotEmpty &&
        tiles.every((t) => !t.unlocked)) {
      return ArenaAchievementsEmpty(
        progression: progression,
        tiles: tiles,
        onOpenBadges: onOpenBadges,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13SectionHeader(
          title: 'Achievements',
          trailingLabel:
              '${progression.achievementsEarned} of ${progression.achievementsTotal}',
          onTrailingTap: onOpenBadges,
        ),
        const SizedBox(height: V13.gapLg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: V13.gapMd),
              Expanded(
                child: _ArenaBadgeTile(badge: tiles[i], onTap: onOpenBadges),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ArenaBadgeTile extends StatelessWidget {
  const _ArenaBadgeTile({required this.badge, required this.onTap});

  final NuvoBadge badge;
  final VoidCallback onTap;

  Color get _accent {
    if (badge.isMilestone || badge.category == 'winning') return V13.gold;
    return switch (badge.category) {
      'performance' => V13.mint,
      'creation' || 'motion' => V13.lilac,
      _ => V13.sky,
    };
  }

  @override
  Widget build(BuildContext context) {
    final numeral = nuvoBadgeNumeralFor(badge.iconKey);
    final icon = nuvoBadgeIconFor(badge.iconKey);
    return V13Pressable(
      onTap: onTap,
      semanticLabel: badge.name,
      child: Column(
        children: [
          if (badge.unlocked)
            numeral != null
                // Numeral badges ("100") need the tile's face, not an icon —
                // mirror V13IconTile's outline/fill with text inside.
                ? Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(V13.radiusTileLg),
                      border: Border.all(color: V13.navy, width: V13.outline),
                      boxShadow: V13.shadow3,
                    ),
                    child: Text(numeral, style: V13.number),
                  )
                : V13IconTile(
                    icon: icon,
                    color: _accent,
                    size: 56,
                    radius: V13.radiusTileLg,
                  )
          else
            V13Card.dashed(
              radius: V13.radiusTileLg,
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(child: Icon(icon, size: 24, color: V13.muted)),
              ),
            ),
          const SizedBox(height: V13.gapXs + 2),
          Text(
            badge.name,
            style: V13.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Compact section-scoped error: message + retry, card-sized so a failed
/// section never blanks the rest of Arena.
class ArenaSectionError extends StatelessWidget {
  const ArenaSectionError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return V13Card(
      padding: const EdgeInsets.symmetric(
        horizontal: V13.gapMd,
        vertical: V13.gapMd + 2,
      ),
      child: Row(
        children: [
          const Icon(Icons.refresh_rounded, size: 20, color: V13.muted),
          const SizedBox(width: V13.gapMd - 2),
          Expanded(
            child: Text(
              message,
              style: V13.caption.copyWith(color: V13.navy),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: V13.gapSm),
          V13Button.secondary(
            label: 'Retry',
            size: V13ButtonSize.small,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
