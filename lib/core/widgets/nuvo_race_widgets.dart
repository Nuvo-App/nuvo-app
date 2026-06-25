import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';
import 'pressable_scale.dart';

// ── RaceLaneRow ───────────────────────────────────────────────────────────────
// Lane-style board row for the Races index. The progress path is the
// dominant visual — not a card border. Layout:
//
//   [3px accent] | title + type pill .............. score
//                | ████░░░░░░░░░░ flag  (progress lane, 5px)
//                | avatars · gap copy
//                | ● recent activity line (optional)

class RaceLaneRow extends StatelessWidget {
  const RaceLaneRow({
    super.key,
    required this.title,
    required this.raceTypeLabel,
    required this.progressPercent,
    required this.scoreLabel,
    this.gapCopy,
    required this.avatars,
    required this.racerCount,
    this.recentActivityLine,
    this.isComplete = false,
    required this.onTap,
  });

  final String title;
  final String raceTypeLabel;
  final int progressPercent;
  final String scoreLabel;
  final String? gapCopy;
  final List<({String initials, String? photoUrl})> avatars;
  final int racerCount;
  final String? recentActivityLine;
  final bool isComplete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = progressPercent.clamp(0, 100);
    final laneColor = isComplete ? NuvoColors.success : NuvoColors.blue;
    final accentColor = isComplete ? NuvoColors.success : NuvoColors.blue;

    return PressableScale(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.divider, width: 0.8),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Left accent strip ──────────────────────────────────────
              Container(width: 3, color: accentColor),

              // ── Content ────────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 13, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row + score
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _RaceTypePill(
                                  label: isComplete
                                      ? 'Done'
                                      : raceTypeLabel,
                                  complete: isComplete,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  title,
                                  style: AppTextStyles.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                scoreLabel,
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: isComplete
                                      ? NuvoColors.success
                                      : NuvoColors.navy,
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 14,
                                color: NuvoColors.muted,
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Progress lane — the dominant visual
                      const SizedBox(height: 12),
                      _LaneProgress(
                        progressPercent: pct,
                        laneColor: laneColor,
                      ),

                      // Crew avatars + gap copy
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          if (avatars.isNotEmpty)
                            NuvoAvatarStack(
                              avatars: avatars,
                              total: racerCount,
                              size: 18,
                              max: 4,
                            ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: gapCopy != null
                                ? RaceGapText(copy: gapCopy!)
                                : Text(
                                    '$racerCount ${racerCount == 1 ? 'racer' : 'racers'}',
                                    style: AppTextStyles.bodySmall,
                                  ),
                          ),
                        ],
                      ),

                      // Recent activity pulse
                      if (recentActivityLine != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: NuvoColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                recentActivityLine!,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: NuvoColors.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Lane progress track ───────────────────────────────────────────────────────
// The centrepiece visual: a 5px track with a dot rider and a flag at the end.

class _LaneProgress extends StatelessWidget {
  const _LaneProgress({
    required this.progressPercent,
    required this.laneColor,
  });

  final int progressPercent;
  final Color laneColor;

  @override
  Widget build(BuildContext context) {
    final pct = progressPercent.clamp(0, 100);
    final progress = pct / 100;
    const trackH = 5.0;
    const dotD = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fill = (width * progress).clamp(0.0, width);

        return SizedBox(
          height: dotD,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: trackH,
                    decoration: BoxDecoration(
                      color: NuvoColors.trackBg,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              // Filled portion
              if (progress > 0)
                Positioned(
                  left: 0,
                  child: Container(
                    width: fill,
                    height: trackH,
                    decoration: BoxDecoration(
                      color: laneColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              // Finish-line flag
              Positioned(
                right: 0,
                child: Icon(
                  Icons.flag_rounded,
                  size: 12,
                  color: progress >= 1 ? laneColor : NuvoColors.border,
                ),
              ),
              // Rider dot
              if (progress > 0 && progress < 1)
                Positioned(
                  left: (fill - dotD / 2).clamp(0.0, width - dotD),
                  child: Container(
                    width: dotD,
                    height: dotD,
                    decoration: BoxDecoration(
                      color: laneColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: NuvoColors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── RaceGapText ───────────────────────────────────────────────────────────────

class RaceGapText extends StatelessWidget {
  const RaceGapText({super.key, required this.copy});
  final String copy;

  @override
  Widget build(BuildContext context) {
    return Text(
      copy,
      style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ── ActionDockChoice ──────────────────────────────────────────────────────────
// Kept for backwards compatibility — move_screen now uses its own _DockAction.

class ActionDockChoice extends StatelessWidget {
  const ActionDockChoice({
    super.key,
    required this.label,
    required this.description,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final String description;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final bg = isPrimary ? NuvoColors.navy : NuvoColors.panel;
    final labelColor = isPrimary ? NuvoColors.white : NuvoColors.navy;
    final descColor = isPrimary
        ? NuvoColors.white.withValues(alpha: 0.55)
        : NuvoColors.muted;

    return PressableScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: isPrimary ? null : Border.all(color: NuvoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.headlineMedium.copyWith(color: labelColor),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: AppTextStyles.bodySmall.copyWith(color: descColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _RaceTypePill ─────────────────────────────────────────────────────────────

class _RaceTypePill extends StatelessWidget {
  const _RaceTypePill({required this.label, this.complete = false});
  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: complete
            ? NuvoColors.success.withValues(alpha: 0.10)
            : NuvoColors.trackBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: complete ? NuvoColors.success : NuvoColors.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
