import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';
import 'nuvo_button.dart';
import 'nuvo_icons.dart';
import 'nuvo_shared_components.dart';
import 'pressable_scale.dart';

/// Race product components for Nuvo.
///
/// These encode product meaning — placement, progress, crew completeness,
/// results, and movement identity — rather than being generic containers.
///
/// Layering:
///   foundations → existing primitives (NuvoAvatar, NuvoRaceLane, NuvoButton)
///   → these race product components → screens
///
/// No generic "FancyCard" abstractions. Each component here exists because it
/// represents a recurring Nuvo product concept that a plain Container cannot
/// express structurally.

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

/// Returns the placement color for [rank] (1=gold, 2=silver, 3=bronze).
Color? _placementColor(int? rank) {
  if (rank == null) return null;
  return switch (rank) {
    1 => NuvoColors.position1,
    2 => NuvoColors.position2,
    3 => NuvoColors.position3,
    _ => null,
  };
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoRacePositionBadge
// ──────────────────────────────────────────────────────────────────────────────

/// Placement badge for a race position.
///
/// Encodes product meaning: 1st/2nd/3rd get medal colors and a crown icon;
/// other positions get a neutral numbered chip. The visual weight differs by
/// placement — the leader's badge is larger and colored, not just "a number
/// in a circle."
class NuvoRacePositionBadge extends StatelessWidget {
  const NuvoRacePositionBadge({
    super.key,
    required this.rank,
    this.size = 30,
    this.onDark = false,
  });

  final int? rank;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (rank == null) {
      return SizedBox(width: size, height: size);
    }

    final isPodium = rank! <= 3;
    final color = _placementColor(rank);
    final bgColor = onDark
        ? (color?.withValues(alpha: 0.22) ??
              NuvoColors.white.withValues(alpha: 0.10))
        : (color?.withValues(alpha: 0.16) ?? NuvoColors.panel);
    final fgColor = onDark
        ? (color ?? NuvoColors.white.withValues(alpha: 0.85))
        : (color ?? NuvoColors.navy);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(NuvoRadii.badge),
      ),
      alignment: Alignment.center,
      child: isPodium && size >= 28
          ? NuvoIcon(NuvoIconType.crown, color: fgColor, size: size * 0.5)
          : Text(
              '$rank',
              style: AppTextStyles.statLarge(
                size * 0.42,
                color: fgColor,
                weight: FontWeight.w800,
              ),
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoRacerStack
// ──────────────────────────────────────────────────────────────────────────────

/// Avatar stack that understands crew completeness.
///
/// When [emptySlots] > 0, renders dashed empty-slot circles to structurally
/// communicate that the race is waiting for crew — not just text saying so.
/// Filled avatars use [NuvoAvatar]; empty slots are a distinct visual shape
/// (dashed outline, plus icon) so the incompleteness is visible at a glance.
class NuvoRacerStack extends StatelessWidget {
  const NuvoRacerStack({
    super.key,
    required this.avatars,
    required this.total,
    this.emptySlots = 0,
    this.size = 28,
    this.max = 4,
    this.borderColor = NuvoColors.white,
  });

  final List<({String initials, String? photoUrl, String id})> avatars;
  final int total;
  final int emptySlots;
  final double size;
  final int max;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final filled = avatars.length;
    final showEmpty = emptySlots > 0;
    final overflow = total > max;
    // Reserve one slot for the +N bubble if overflow.
    final visibleFilled = overflow
        ? filled.clamp(0, max - 1)
        : filled.clamp(0, max);
    final visibleEmpty = showEmpty
        ? (overflow
              ? emptySlots.clamp(0, (max - visibleFilled - 1).clamp(0, max))
              : emptySlots.clamp(0, max - visibleFilled))
        : 0;

    final totalSlots = overflow
        ? visibleFilled + 1 + visibleEmpty
        : visibleFilled + visibleEmpty;

    if (totalSlots == 0) return const SizedBox.shrink();

    final overlap = (size * 0.32).clamp(8.0, 13.0);
    final stepWidth = size - overlap;
    final stackWidth = size + stepWidth * (totalSlots - 1);
    final ringWidth = size <= NuvoAvatarSizes.xs ? 1.5 : 2.0;

    return SizedBox(
      width: stackWidth,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < visibleFilled; i++)
            Positioned(
              left: i * stepWidth,
              child: NuvoAvatar(
                initials: avatars[i].initials,
                photoUrl: avatars[i].photoUrl,
                size: size,
                bgColor: nuvoAvatarColorFor(avatars[i].id),
                textColor: NuvoColors.white,
                borderColor: borderColor,
                borderWidth: ringWidth,
              ),
            ),
          for (var j = 0; j < visibleEmpty; j++)
            Positioned(
              left: (visibleFilled + j) * stepWidth,
              child: _EmptyCrewSlot(size: size),
            ),
          if (overflow)
            Positioned(
              left: (visibleFilled + visibleEmpty) * stepWidth,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NuvoColors.panel,
                  border: Border.all(color: borderColor, width: ringWidth),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+${total - visibleFilled}',
                  style: TextStyle(
                    fontSize: (size * 0.3).clamp(6.0, 10.0),
                    fontWeight: FontWeight.w800,
                    color: NuvoColors.navy,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyCrewSlot extends StatelessWidget {
  const _EmptyCrewSlot({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: NuvoColors.page,
        border: Border.all(
          color: NuvoColors.border.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.add_rounded,
        size: size * 0.42,
        color: NuvoColors.textDim,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoRaceProgressLane
// ──────────────────────────────────────────────────────────────────────────────

/// Progress lane with target and distance-to-go context.
///
/// Wraps [NuvoRaceLane] with a header line showing the current score and the
/// finish line, so progress is visible as competition, not just a bar.
class NuvoRaceProgressLane extends StatelessWidget {
  const NuvoRaceProgressLane({
    super.key,
    required this.progressPercent,
    required this.progressLabel,
    required this.targetLabel,
    this.onDark = false,
    this.trackHeight = 6,
    this.dotDiameter = 12,
    this.compact = false,
  });

  final int progressPercent;
  final String progressLabel;
  final String targetLabel;
  final bool onDark;
  final double trackHeight;
  final double dotDiameter;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final labelColor = onDark
        ? NuvoColors.white.withValues(alpha: 0.85)
        : NuvoColors.navy;
    final targetColor = onDark
        ? NuvoColors.white.withValues(alpha: 0.55)
        : NuvoColors.textMuted;
    final valueStyle = AppTextStyles.statLarge(
      compact ? 13 : 15,
      color: labelColor,
      weight: FontWeight.w800,
    );
    final targetStyle = AppTextStyles.raceRowMeta.copyWith(color: targetColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: progressLabel, style: valueStyle),
              TextSpan(text: ' to $targetLabel', style: targetStyle),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: compact ? 6 : NuvoSpacing.sm),
        NuvoRaceLane(
          progressPercent: progressPercent,
          onDark: onDark,
          trackHeight: trackHeight,
          dotDiameter: dotDiameter,
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoWaitingCrewSummary
// ──────────────────────────────────────────────────────────────────────────────

/// Summary row for races waiting for crew.
///
/// Structurally communicates incompleteness: shows filled avatars + empty crew
/// slots (dashed circles with +) rather than just a text count. The visual
/// shape itself says "someone is missing."
class NuvoWaitingCrewSummary extends StatelessWidget {
  const NuvoWaitingCrewSummary({
    super.key,
    required this.raceCount,
    required this.totalWaitingSlots,
    required this.avatars,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final int raceCount;
  final int totalWaitingSlots;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '$raceCount ${raceCount == 1 ? 'race' : 'races'} need crew';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PressableScale(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NuvoSpacing.md,
              vertical: NuvoSpacing.md,
            ),
            decoration: BoxDecoration(
              color: NuvoColors.crewWaitingTint.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(NuvoRadii.card),
              border: Border.all(
                color: NuvoColors.crewWaiting.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Empty-slot icon — structurally says "missing people"
                const _CrewSlotIcon(size: 32),
                const SizedBox(width: NuvoSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Waiting for crew',
                        style: AppTextStyles.raceRowTitle.copyWith(
                          color: NuvoColors.navy,
                        ),
                      ),
                      Text(subtitle, style: AppTextStyles.raceRowMeta),
                    ],
                  ),
                ),
                if (avatars.isNotEmpty) ...[
                  NuvoRacerStack(
                    avatars: avatars,
                    total: avatars.length,
                    emptySlots: totalWaitingSlots.clamp(0, 3),
                    size: 24,
                    max: 3,
                  ),
                  const SizedBox(width: NuvoSpacing.sm),
                ],
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: NuvoColors.textMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...children,
      ],
    );
  }
}

class _CrewSlotIcon extends StatelessWidget {
  const _CrewSlotIcon({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: NuvoColors.crewWaitingTint,
        borderRadius: BorderRadius.circular(NuvoRadii.badge),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.group_add_rounded,
        color: NuvoColors.crewWaiting,
        size: size * 0.5,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoFinishedSummary
// ──────────────────────────────────────────────────────────────────────────────

/// Summary row for finished races.
///
/// Structurally emphasizes results: a placement badge (crown for 1st, number
/// for others) replaces the generic checkmark. The visual shape says
/// "this is over, here is where you placed."
class NuvoFinishedSummary extends StatelessWidget {
  const NuvoFinishedSummary({
    super.key,
    required this.raceCount,
    required this.wonCount,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final int raceCount;
  final int wonCount;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '$raceCount ${raceCount == 1 ? 'race' : 'races'}'
        ' · $wonCount ${wonCount == 1 ? 'win' : 'wins'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PressableScale(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NuvoSpacing.md,
              vertical: NuvoSpacing.md,
            ),
            decoration: BoxDecoration(
              color: NuvoColors.raceFinished.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(NuvoRadii.card),
              border: Border.all(
                color: NuvoColors.raceFinished.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Result icon — crown if won, check otherwise
                _ResultIcon(size: 32, won: wonCount > 0),
                const SizedBox(width: NuvoSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Finished',
                        style: AppTextStyles.raceRowTitle.copyWith(
                          color: NuvoColors.navy,
                        ),
                      ),
                      Text(subtitle, style: AppTextStyles.raceRowMeta),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: NuvoColors.textMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...children,
      ],
    );
  }
}

class _ResultIcon extends StatelessWidget {
  const _ResultIcon({required this.size, required this.won});
  final double size;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: won
            ? NuvoColors.position1.withValues(alpha: 0.16)
            : NuvoColors.raceFinished.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NuvoRadii.badge),
      ),
      alignment: Alignment.center,
      child: won
          ? NuvoIcon(
              NuvoIconType.crown,
              color: NuvoColors.position1,
              size: size * 0.5,
            )
          : Icon(
              Icons.check_rounded,
              color: NuvoColors.raceFinished,
              size: size * 0.5,
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoQuickStart
// ──────────────────────────────────────────────────────────────────────────────

/// Quick start tile for a movement race.
///
/// Leads with movement identity (the exercise icon is the primary visual
/// element, not a generic container). The target number is set in tabular
/// figures so it reads as a score/target, not a label. Compact and scannable.
class NuvoQuickStart extends StatelessWidget {
  const NuvoQuickStart({
    super.key,
    required this.icon,
    required this.movementName,
    required this.target,
    required this.onTap,
  });

  final IconData icon;
  final String movementName;
  final String target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width < 400 ? 140 : 150,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: NuvoSpacing.md,
          vertical: NuvoSpacing.md,
        ),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.sm),
          border: NuvoBorders.quiet,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Movement identity icon — the primary visual
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: NuvoColors.panel,
                borderRadius: BorderRadius.circular(NuvoRadii.badge),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: NuvoColors.navy, size: 18),
            ),
            const SizedBox(width: NuvoSpacing.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    movementName,
                    style: AppTextStyles.raceRowTitle.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    target,
                    style: AppTextStyles.statLarge(
                      12,
                      color: NuvoColors.blue,
                      weight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoFeaturedRaceCard
// ──────────────────────────────────────────────────────────────────────────────

/// The one loud "continue competing" surface.
///
/// Shows competition, not just a navy rectangle with text. Visible elements:
/// - activity + target kicker
/// - race title
/// - racer stack (the people you're competing against)
/// - your rank badge
/// - progress lane with score and distance-to-go
/// - "View leaderboard" action
///
/// Reserved signature shadow — this is the one surface that earns it.
class NuvoFeaturedRaceCard extends StatelessWidget {
  const NuvoFeaturedRaceCard({
    super.key,
    required this.activityLabel,
    required this.targetLabel,
    required this.raceTitle,
    required this.progressPercent,
    required this.progressLabel,
    required this.racerStack,
    required this.rank,
    required this.onOpen,
    this.actionLabel = 'View leaderboard',
  });

  final String activityLabel;
  final String targetLabel;
  final String raceTitle;
  final int progressPercent;
  final String progressLabel;
  final Widget racerStack;
  final int? rank;
  final VoidCallback onOpen;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final rankStr = rank != null ? ' · You\'re ${_ordinal(rank!)}' : '';

    return PressableScale(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(NuvoSpacing.xl),
        decoration: BoxDecoration(
          color: NuvoColors.navy,
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          boxShadow: AppShadows.hardMedium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kicker: activity + target
            Text(
              '$activityLabel · $targetLabel',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: NuvoSpacing.sm),
            // Title
            Text(
              raceTitle,
              style: AppTextStyles.featuredRaceTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: NuvoSpacing.sm),
            // Racer stack + rank
            Row(
              children: [
                racerStack,
                const SizedBox(width: NuvoSpacing.sm),
                Text(
                  rankStr.isEmpty
                      ? 'In progress'
                      : 'You\'re ${_ordinal(rank!)}',
                  style: AppTextStyles.raceRowMeta.copyWith(
                    color: NuvoColors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NuvoSpacing.lg),
            // Progress lane with score + distance-to-go
            NuvoRaceProgressLane(
              progressPercent: progressPercent,
              progressLabel: progressLabel,
              targetLabel: targetLabel,
              onDark: true,
              trackHeight: 6,
              dotDiameter: 12,
            ),
            const SizedBox(height: NuvoSpacing.lg),
            NuvoPrimaryButton(
              label: actionLabel,
              expand: true,
              small: true,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoRaceRow
// ──────────────────────────────────────────────────────────────────────────────

/// Compact race row for the "Your races" list.
///
/// Shows competition info, not just a title and meta line:
/// - rank/position badge on the left (structural placement)
/// - race title
/// - racer stack (the people)
/// - progress percent as a stat number
///
/// Tappable → Race Detail.
class NuvoRaceRow extends StatelessWidget {
  const NuvoRaceRow({
    super.key,
    required this.raceTitle,
    required this.rank,
    required this.participantCount,
    required this.progressPercent,
    required this.avatars,
    required this.onTap,
  });

  final String raceTitle;
  final int? rank;
  final int participantCount;
  final int progressPercent;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: raceTitle,
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(
            horizontal: NuvoSpacing.md,
            vertical: NuvoSpacing.md,
          ),
          child: Row(
            children: [
              // Position badge — structural placement
              NuvoRacePositionBadge(rank: rank, size: 30),
              const SizedBox(width: NuvoSpacing.md),
              // Title + racer count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      raceTitle,
                      style: AppTextStyles.raceRowTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$participantCount ${participantCount == 1 ? 'racer' : 'racers'}',
                      style: AppTextStyles.raceRowMeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              // Racer stack — the people
              if (avatars.isNotEmpty)
                NuvoRacerStack(
                  avatars: avatars,
                  total: participantCount,
                  size: 24,
                  max: 3,
                ),
              const SizedBox(width: NuvoSpacing.sm),
              // Progress as a stat number
              Text(
                '$progressPercent%',
                style: AppTextStyles.statLarge(
                  15,
                  color: NuvoColors.blue,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// NuvoFinishedRaceRow
// ──────────────────────────────────────────────────────────────────────────────

/// Compact race row for finished races.
///
/// Structurally different from [NuvoRaceRow]: shows placement badge (crown for
/// 1st) and final result, NOT progress percent. The absence of a progress bar
/// and the presence of a placement badge communicates "this is over."
class NuvoFinishedRaceRow extends StatelessWidget {
  const NuvoFinishedRaceRow({
    super.key,
    required this.raceTitle,
    required this.rank,
    required this.participantCount,
    required this.avatars,
    required this.onTap,
  });

  final String raceTitle;
  final int? rank;
  final int participantCount;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final placementStr = rank != null ? _ordinal(rank!) : '--';

    return Semantics(
      button: true,
      label: raceTitle,
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(
            horizontal: NuvoSpacing.md,
            vertical: NuvoSpacing.md,
          ),
          child: Row(
            children: [
              // Placement badge — crown for 1st, number for others
              NuvoRacePositionBadge(rank: rank, size: 30),
              const SizedBox(width: NuvoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      raceTitle,
                      style: AppTextStyles.raceRowTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$participantCount ${participantCount == 1 ? 'racer' : 'racers'}',
                      style: AppTextStyles.raceRowMeta,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              if (avatars.isNotEmpty)
                NuvoRacerStack(
                  avatars: avatars,
                  total: participantCount,
                  size: 24,
                  max: 3,
                ),
              const SizedBox(width: NuvoSpacing.sm),
              // Placement label — NOT a progress percent
              Text(
                placementStr,
                style: AppTextStyles.placementLabel(
                  color: _placementColor(rank) ?? NuvoColors.textMuted,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
