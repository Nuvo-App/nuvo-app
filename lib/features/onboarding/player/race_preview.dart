import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/v13.dart';
import '../flow/onboarding_copy.dart';

/// What the race is called for a given Q1 answer. The answer itself is
/// stored as the chip label (so every consumer reads the same value); this
/// maps it to the race's name. Fitness is the camera-provable squat race
/// the tour walks through.
String obRaceActivity(String? q1) => switch (q1) {
  ObCopy.q1Fitness => 'Squat',
  ObCopy.q1Running => 'Running',
  ObCopy.q1Reading => 'Reading',
  ObCopy.q1Studying => 'Studying',
  ObCopy.q1Gaming => 'Gaming',
  ObCopy.q1Other => 'First',
  _ => 'Squat',
};

/// "Squat Race" — the live preview title on S8.
String obRacePreviewTitle(String? q1) =>
    ObCopy.q1Preview(obRaceActivity(q1));

/// "Squat Race · First to 10" — the seeded practice race name for S9/S10.
String obPracticeRaceName(String? q1) =>
    ObCopy.practiceRaceName(obRaceActivity(q1));

/// Small race card used as the hero on S8 and the centerpiece of S9. The
/// title cross-fades with a spring as the answer changes.
class ObRacePreviewCard extends StatelessWidget {
  const ObRacePreviewCard({
    super.key,
    required this.title,
    this.subtitle,
    this.color = V13.mint,
    this.racers = 3,
    this.showPracticeTag = true,
  });

  final String title;
  final String? subtitle;
  final Color color;

  /// Number of racer tokens on the lane (1 = solo, 3 = with friends).
  final int racers;
  final bool showPracticeTag;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: NuvoFloat(
        child: Container(
          key: const ValueKey('race-preview-card'),
          width: 300,
          padding: const EdgeInsets.all(V13.gapLg),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(V13.radiusCard),
            border: Border.all(color: V13.navy, width: V13.outlineThick),
            boxShadow: V13.shadow6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showPracticeTag) ...[
                const V13Pill(label: ObCopy.practiceTag),
                const SizedBox(height: V13.gapMd),
              ],
              AnimatedSwitcher(
                duration: NuvoMotion.springDuration,
                switchInCurve: NuvoMotion.spring,
                child: Text(
                  title,
                  key: ValueKey(title),
                  style: V13.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: V13.bodyStrong),
              ],
              const SizedBox(height: V13.gapLg),
              _Lane(racers: racers),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lane extends StatelessWidget {
  const _Lane({required this.racers});

  final int racers;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < racers; i++) ...[
          if (i > 0) const SizedBox(width: V13.gapSm),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: V13.card,
              shape: BoxShape.circle,
              border: Border.all(
                color: i == 0 ? V13.blue : V13.navy,
                width: V13.outlineThick,
              ),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: V13.muted,
              size: 26,
            ),
          ),
        ],
        const Spacer(),
        const Icon(Icons.flag_rounded, color: V13.navy, size: 28),
      ],
    );
  }
}
