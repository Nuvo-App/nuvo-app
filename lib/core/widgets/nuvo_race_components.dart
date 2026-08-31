import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';
import 'pressable_scale.dart';

/// Canonical race components for Nuvo.
///
/// Visual grammar:
///   RaceHero    — the one loud navy surface (Compete featured, Verify Up Next)
///   RaceRow     — active race row (Compete "Your races", Verify "Also ready")
///   RaceResultRow — finished race row (Compete Finished, Verify Completed)
///   RaceActivityRow — recent proof activity (Verify Recent)
///
/// Shared primitives:
///   RacePlacement — quiet rank treatment (not a colored badge)
///   RaceProgress  — progress that works at 0%, partial, and complete
///   RacePeople    — avatar stack with count
///
/// Design rules:
///   - Movement + title dominate. Badges/pills are secondary.
///   - Rank is a quiet number, not a colored square. Podium gets color only
///     on the number itself, not a container.
///   - Progress at 0% shows a start-line marker, not an empty bar.
///   - No chevrons. Rows are tappable; the press scale is the affordance.

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
// RacePlacement — quiet rank, not a colored badge
// ──────────────────────────────────────────────────────────────────────────────

/// Quiet placement treatment.
///
/// Shows rank as a number with placement color (gold/silver/bronze for 1-3).
/// No container, no badge shape — just the number. The color communicates
/// podium status without a generic rounded square.
class RacePlacement extends StatelessWidget {
  const RacePlacement({
    super.key,
    required this.rank,
    this.size = 16,
    this.onDark = false,
    this.prefix = '#',
  });

  final int? rank;
  final double size;
  final bool onDark;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    if (rank == null) return const SizedBox.shrink();

    final color = _placementColor(rank);
    final fgColor = onDark
        ? (color ?? NuvoColors.white.withValues(alpha: 0.85))
        : (color ?? NuvoColors.navy);

    return Text(
      '$prefix$rank',
      style: AppTextStyles.statLarge(
        size,
        color: fgColor,
        weight: FontWeight.w800,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceProgress — progress that works at every state
// ──────────────────────────────────────────────────────────────────────────────

/// Race progress track.
///
/// - 0%: start-line marker (a small dot at the left). No empty bar.
/// - partial: filled portion + position dot
/// - 100%: finish-line check at the right
///
/// Does NOT look like a Material slider. The track is thin, the fill is
/// blue (or green at completion), and the position marker has a navy ring
/// so it reads as "you are here on the track."
class RaceProgress extends StatelessWidget {
  const RaceProgress({
    super.key,
    required this.progressPercent,
    this.onDark = false,
    this.trackHeight = 3.0,
    this.dotDiameter = 10.0,
  });

  final int progressPercent;
  final bool onDark;
  final double trackHeight;
  final double dotDiameter;

  @override
  Widget build(BuildContext context) {
    final progress = (progressPercent / 100).clamp(0.0, 1.0);
    final trackColor = onDark
        ? Colors.white.withValues(alpha: 0.16)
        : NuvoColors.trackBg;
    final fillColor = progress >= 1
        ? NuvoColors.success
        : NuvoColors.actionBlue;

    return SizedBox(
      height: dotDiameter,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final fillWidth = (totalWidth * progress).clamp(0.0, totalWidth);

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track
              Container(
                height: trackHeight,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(trackHeight / 2),
                ),
              ),
              // Fill (only when progress > 0)
              if (progress > 0)
                Container(
                  width: fillWidth,
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),
              // 0%: start-line marker — small, quiet
              if (progress == 0)
                Positioned(
                  left: 0,
                  child: Container(
                    width: dotDiameter * 0.7,
                    height: dotDiameter * 0.7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: onDark
                          ? Colors.white.withValues(alpha: 0.30)
                          : NuvoColors.border,
                    ),
                  ),
                ),
              // Partial: position dot with navy ring
              if (progress > 0 && progress < 1)
                Positioned(
                  left: (fillWidth - dotDiameter / 2).clamp(
                    0.0,
                    totalWidth - dotDiameter,
                  ),
                  child: Container(
                    width: dotDiameter,
                    height: dotDiameter,
                    decoration: BoxDecoration(
                      color: fillColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: NuvoColors.inkNavy, width: 1.5),
                    ),
                  ),
                ),
              // 100%: finish-line check at right
              if (progress >= 1)
                Positioned(
                  right: 0,
                  child: Container(
                    width: dotDiameter,
                    height: dotDiameter,
                    decoration: BoxDecoration(
                      color: NuvoColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: NuvoColors.inkNavy, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 7,
                      color: NuvoColors.white,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RacePeople — avatar stack with count
// ──────────────────────────────────────────────────────────────────────────────

/// Avatar stack that understands crew completeness.
///
/// Filled avatars + dashed empty slots when waiting for crew.
/// The +N overflow bubble shows total people beyond the visible stack.
class RacePeople extends StatelessWidget {
  const RacePeople({
    super.key,
    required this.avatars,
    required this.total,
    this.emptySlots = 0,
    this.size = 24,
    this.max = 3,
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
// RaceProgressLabel — score + target context line
// ──────────────────────────────────────────────────────────────────────────────

/// Progress context line: "12 reps to 100 reps" or "20% to finish".
class RaceProgressLabel extends StatelessWidget {
  const RaceProgressLabel({
    super.key,
    required this.progressLabel,
    required this.targetLabel,
    this.onDark = false,
    this.compact = false,
  });

  final String progressLabel;
  final String targetLabel;
  final bool onDark;
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

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: progressLabel, style: valueStyle),
          TextSpan(text: ' to $targetLabel', style: targetStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceHero — the one loud navy surface
// ──────────────────────────────────────────────────────────────────────────────

/// Hero race card. The strongest object on the page.
///
/// Shared by Compete (featured race) and Verify (Up Next). The [variant]
/// controls the CTA label and whether rank is shown.
///
/// Layout:
///   kicker (movement · target)
///   race title
///   progress label + progress track
///   people + placement (inline, not stacked)
///   CTA
class RaceHero extends StatelessWidget {
  const RaceHero({
    super.key,
    required this.activityLabel,
    required this.targetLabel,
    required this.raceTitle,
    required this.progressPercent,
    required this.progressLabel,
    required this.racerStack,
    this.rank,
    required this.onOpen,
    this.actionLabel = 'View leaderboard',
    this.ctaIcon,
    this.showRank = true,
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
  final IconData? ctaIcon;
  final bool showRank;

  @override
  Widget build(BuildContext context) {
    final hasProof = progressPercent > 0;

    return PressableScale(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          border: Border.all(color: NuvoColors.navy, width: 2),
          boxShadow: AppShadows.hardLarge,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NuvoRadii.lg - 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── White body: race identity + track lane ──
              Container(
                color: NuvoColors.surface,
                padding: const EdgeInsets.fromLTRB(
                  NuvoSpacing.xl,
                  NuvoSpacing.xl,
                  NuvoSpacing.xl,
                  NuvoSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Race title
                    Text(
                      raceTitle,
                      style: AppTextStyles.featuredRaceTitle.copyWith(
                        color: NuvoColors.navy,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Movement · target
                    Text(
                      '$activityLabel · $targetLabel',
                      style: AppTextStyles.raceRowMeta.copyWith(
                        color: NuvoColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: NuvoSpacing.xl),
                    // Race lane — prominent track on white
                    RaceProgress(
                      progressPercent: progressPercent,
                      onDark: false,
                      trackHeight: 5,
                      dotDiameter: 16,
                    ),
                    const SizedBox(height: 8),
                    // Lane context
                    Row(
                      children: [
                        if (!hasProof)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: NuvoColors.actionBlue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Start line',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: NuvoColors.navy,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          )
                        else
                          Expanded(
                            child: RaceProgressLabel(
                              progressLabel: progressLabel,
                              targetLabel: targetLabel,
                              onDark: false,
                              compact: true,
                            ),
                          ),
                        if (showRank && rank != null && hasProof)
                          Text(
                            _ordinal(rank!),
                            style: AppTextStyles.placementLabel(
                              color: _placementColor(rank) ?? NuvoColors.navy,
                              size: 13,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // ── Blue action strip: crew + CTA ──
              Container(
                color: NuvoColors.actionBlue,
                padding: const EdgeInsets.symmetric(
                  horizontal: NuvoSpacing.xl,
                  vertical: NuvoSpacing.md,
                ),
                child: Row(
                  children: [
                    racerStack,
                    const Spacer(),
                    GestureDetector(
                      onTap: onOpen,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actionLabel,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: NuvoColors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            ctaIcon ?? Icons.arrow_forward_rounded,
                            color: NuvoColors.white,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
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
// RaceRow — active race row
// ──────────────────────────────────────────────────────────────────────────────

/// Active race row for "Your races" lists.
///
/// Answers quickly: What race? Where am I? How far along? Who am I racing?
///
/// Layout:
///   race title (dominant)
///   movement · progress label (meta line)
///   progress track (compact)
///   people + placement (right-aligned, quiet)
class RaceRow extends StatelessWidget {
  const RaceRow({
    super.key,
    required this.raceTitle,
    required this.movementLabel,
    required this.progressLabel,
    required this.progressPercent,
    required this.rank,
    required this.participantCount,
    required this.avatars,
    required this.onTap,
  });

  final String raceTitle;
  final String movementLabel;
  final String progressLabel;
  final int progressPercent;
  final int? rank;
  final int participantCount;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasProof = progressPercent > 0;

    return Semantics(
      button: true,
      label: raceTitle,
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: NuvoSpacing.md,
            vertical: NuvoSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (hasProof) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: NuvoColors.actionBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: Text(
                            raceTitle,
                            style: AppTextStyles.raceRowTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasProof
                          ? '$movementLabel · $progressLabel'
                          : movementLabel,
                      style: AppTextStyles.raceRowMeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasProof) ...[
                      const SizedBox(height: 6),
                      RaceProgress(
                        progressPercent: progressPercent,
                        trackHeight: 3,
                        dotDiameter: 9,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              // Right side: placement + people
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasProof)
                    RacePlacement(rank: rank, size: 15)
                  else
                    Text(
                      'At start',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.textDim,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                  if (avatars.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    RacePeople(
                      avatars: avatars,
                      total: participantCount,
                      size: 20,
                      max: 3,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceResultRow — finished race row
// ──────────────────────────────────────────────────────────────────────────────

/// Finished race row. Shows placement, not progress.
///
/// Layout:
///   race title (dominant)
///   movement · racer count (meta line)
///   people + placement (right-aligned)
///
/// No progress bar — the absence of progress communicates "this is over."
class RaceResultRow extends StatelessWidget {
  const RaceResultRow({
    super.key,
    required this.raceTitle,
    required this.movementLabel,
    required this.rank,
    required this.participantCount,
    required this.avatars,
    required this.onTap,
  });

  final String raceTitle;
  final String movementLabel;
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
                    const SizedBox(height: 3),
                    Text(
                      '$movementLabel · $participantCount ${participantCount == 1 ? 'racer' : 'racers'}',
                      style: AppTextStyles.raceRowMeta,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              if (avatars.isNotEmpty) ...[
                RacePeople(
                  avatars: avatars,
                  total: participantCount,
                  size: 22,
                  max: 3,
                ),
                const SizedBox(width: NuvoSpacing.sm),
              ],
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

// ──────────────────────────────────────────────────────────────────────────────
// RaceActivityRow — recent proof activity
// ──────────────────────────────────────────────────────────────────────────────

/// Recent proof activity row for Verify Recent.
///
/// Prioritizes race/movement and verification outcome, NOT the actor.
/// The actor is secondary (small avatar) because it's usually the same user.
///
/// Layout:
///   small avatar (secondary)
///   race title (dominant)
///   movement · value · status (meta line)
///   status indicator (right)
class RaceActivityRow extends StatelessWidget {
  const RaceActivityRow({
    super.key,
    required this.raceTitle,
    required this.movementLabel,
    required this.actorName,
    required this.actorInitial,
    required this.actorPhotoUrl,
    required this.actorId,
    required this.valueStr,
    required this.statusLabel,
    required this.statusColor,
    required this.onTap,
  });

  final String raceTitle;
  final String movementLabel;
  final String actorName;
  final String actorInitial;
  final String? actorPhotoUrl;
  final String actorId;
  final String? valueStr;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$raceTitle · $statusLabel',
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
              // Small avatar — secondary
              NuvoAvatar(
                initials: actorInitial,
                photoUrl: actorPhotoUrl,
                size: 28,
                bgColor: nuvoAvatarColorFor(actorId),
                textColor: NuvoColors.white,
              ),
              const SizedBox(width: NuvoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      raceTitle,
                      style: AppTextStyles.raceRowTitle.copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$movementLabel${valueStr != null ? ' · $valueStr' : ''}',
                      style: AppTextStyles.raceRowMeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              // Status — quiet text, no pill container
              Text(
                statusLabel,
                style: AppTextStyles.labelSmall.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
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
// RaceSummary — waiting/finished summary header
// ──────────────────────────────────────────────────────────────────────────────

/// Summary row for waiting-for-crew races.
///
/// Shows the incompleteness structurally: filled avatars + empty slots.
class RaceWaitingSummary extends StatelessWidget {
  const RaceWaitingSummary({
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
              color: NuvoColors.surface,
              borderRadius: BorderRadius.circular(NuvoRadii.md),
              border: NuvoBorders.hero,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Waiting for crew',
                        style: AppTextStyles.sectionTitle,
                      ),
                      Text(subtitle, style: AppTextStyles.raceRowMeta),
                    ],
                  ),
                ),
                if (avatars.isNotEmpty) ...[
                  RacePeople(
                    avatars: avatars,
                    total: avatars.length,
                    emptySlots: totalWaitingSlots.clamp(0, 3),
                    size: 22,
                    max: 3,
                  ),
                  const SizedBox(width: NuvoSpacing.sm),
                ],
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: NuvoColors.textDim,
                    size: 18,
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

/// Summary row for finished races.
class RaceFinishedSummary extends StatelessWidget {
  const RaceFinishedSummary({
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
              color: NuvoColors.surface,
              borderRadius: BorderRadius.circular(NuvoRadii.md),
              border: NuvoBorders.hero,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Finished', style: AppTextStyles.sectionTitle),
                      Text(subtitle, style: AppTextStyles.raceRowMeta),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: NuvoColors.textDim,
                    size: 18,
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

// ──────────────────────────────────────────────────────────────────────────────
// RaceQuickStart — quick start tile
// ──────────────────────────────────────────────────────────────────────────────

/// Quick start tile. Movement identity leads, target is secondary.
class RaceQuickStart extends StatelessWidget {
  const RaceQuickStart({
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
        padding: const EdgeInsets.symmetric(
          horizontal: NuvoSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          border: NuvoBorders.hero,
        ),
        child: Row(
          children: [
            Icon(icon, color: NuvoColors.navy, size: 20),
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
                  const SizedBox(height: 2),
                  Text(
                    target,
                    style: AppTextStyles.statLarge(
                      11,
                      color: NuvoColors.muted,
                      weight: FontWeight.w700,
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
// Legacy aliases — keep old names working during migration
// ──────────────────────────────────────────────────────────────────────────────

/// Legacy alias for [RacePeople].
typedef NuvoRacerStack = RacePeople;

/// Legacy alias for [RaceProgress].
/// Note: old NuvoRaceLane had a different API; use RaceProgress directly.
class NuvoRaceLane extends RaceProgress {
  const NuvoRaceLane({
    super.key,
    required super.progressPercent,
    super.onDark = false,
    super.trackHeight = 3.0,
    super.dotDiameter = 12.0,
    Duration delay = Duration.zero,
  }) : super();
}

/// Legacy alias for [RaceProgressLabel].
typedef NuvoRaceProgressLane = RaceProgressLabel;

/// Legacy alias for [RaceWaitingSummary].
typedef NuvoWaitingCrewSummary = RaceWaitingSummary;

/// Legacy alias for [RaceFinishedSummary].
typedef NuvoFinishedSummary = RaceFinishedSummary;

/// Legacy alias for [RaceQuickStart].
typedef NuvoQuickStart = RaceQuickStart;

/// Legacy alias for [RaceHero].
typedef NuvoFeaturedRaceCard = RaceHero;

/// Legacy alias for [RaceRow].
typedef NuvoRaceRow = RaceRow;

/// Legacy alias for [RaceResultRow].
typedef NuvoFinishedRaceRow = RaceResultRow;
