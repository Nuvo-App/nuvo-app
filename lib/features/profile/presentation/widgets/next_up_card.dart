import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_geometry.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/nuvo_motion.dart';
import '../../../../core/widgets/nuvo_progress_bar.dart';
import '../../data/progression_models.dart';
import 'nuvo_badges.dart';

/// The one achievement in reach — a locked goal with live canonical
/// progress that taps straight back into racing. Unboxed: it lives on the
/// page like the rest of the identity.
class NextUpCard extends StatelessWidget {
  const NextUpCard({super.key, required this.next});

  /// The locked achievement closest to being earned.
  final NuvoBadge next;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final accent = nuvoBadgeAccent(next);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'NEXT UP',
              style: AppTextStyles.labelUppercase(
                10,
                color: c.inkSubtle,
              ).copyWith(color: c.inkSubtle),
            ),
            const Spacer(),
            NuvoPressable(
              onTap: () => context.go('/compete'),
              haptic: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Race toward it',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: NuvoColors.blue,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: NuvoSpacing.sm),
        // The whole strip is the mission — tap it and you're back in a race
        // earning toward the goal. No badge here: the count and the progress
        // line are the anchors, the artifact only exists once it's earned.
        NuvoPressable(
          onTap: () => context.go('/compete'),
          scale: 0.99,
          haptic: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A short mission rail in the goal's own accent —
                    // bounded to the mission block (name → progress bar),
                    // never a full-height divider.
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                    const SizedBox(width: NuvoSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  next.name,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: c.ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (next.threshold != null) ...[
                                const SizedBox(width: NuvoSpacing.sm),
                                Text(
                                  '${next.progressValue} / ${next.threshold}',
                                  style: AppTextStyles.statLarge(
                                    15,
                                    color: accent,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (next.description != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              next.description!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: c.inkMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (next.threshold != null) ...[
                            const SizedBox(height: NuvoSpacing.sm),
                            NuvoProgressBar(
                              value: next.goalProgress,
                              height: 10,
                              color: NuvoColors.blue,
                              trackColor: c.track,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (next.threshold != null &&
                  next.threshold! - next.progressValue == 1) ...[
                const SizedBox(height: 6),
                // One-to-go rides below the rail — indented to the
                // mission column, not bounded by it.
                Padding(
                  padding: const EdgeInsets.only(left: NuvoSpacing.md + 3),
                  child: Text(
                    switch (next.statKey) {
                      'wins' => 'ONE MORE WIN',
                      'races' => 'ONE MORE RACE',
                      'proofs' => 'ONE MORE PROOF',
                      _ => 'ONE TO GO',
                    },
                    style: AppTextStyles.labelUppercase(
                      10,
                    ).copyWith(color: accent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
