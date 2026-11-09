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
String obRacePreviewTitle(String? q1) => ObCopy.q1Preview(obRaceActivity(q1));

/// "Squat Race · First to 10" — the seeded practice race name for S9/S10.
String obPracticeRaceName(String? q1) =>
    ObCopy.practiceRaceName(obRaceActivity(q1));

/// Selected-state fill: the blue wash blended onto the card colour so the
/// hard shadow plate behind a pressable never shows through.
final Color obSelectedFill = Color.alphaBlend(
  V13.blue.withValues(alpha: .14),
  V13.card,
);

/// Hero height for the player segment: roomy on tall phones, compact on
/// small ones, and tight while the keyboard is up. Cards scale down to fit.
double obHeroHeight(BuildContext context, {double tall = 240, double? small}) {
  final h = MediaQuery.sizeOf(context).height;
  return h < 700 ? (small ?? tall - 56) : tall;
}

/// Small race card used as the hero on S8 and the centerpiece of S9. The
/// title cross-fades with a spring as the answer changes. Adapts to the hero
/// slot: under 200px of height it drops to a compact lane.
class ObRacePreviewCard extends StatelessWidget {
  const ObRacePreviewCard({
    super.key,
    required this.title,
    this.subtitle,
    this.color = V13.mint,
    this.racers = 3,
    this.showPracticeTag = true,
    this.liveTag,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Color color;

  /// Number of racer tokens on the lane (1 = solo, 3 = with friends). Zero
  /// hides the lane.
  final int racers;
  final bool showPracticeTag;

  /// Replaces the practice tag when set (S9 shows a mint "Live" pill).
  final Widget? liveTag;

  /// Optional row under the lane/subtitle (S9's build bar).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 200;
        final gap = compact ? V13.gapSm : V13.gapMd;
        return Center(
          child: NuvoFloat(
            child: Container(
              key: const ValueKey('race-preview-card'),
              constraints: const BoxConstraints(maxWidth: 320),
              padding: EdgeInsets.all(compact ? V13.gapMd : V13.gapLg),
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
                  if (liveTag != null)
                    liveTag!
                  else if (showPracticeTag)
                    const V13Pill(label: ObCopy.practiceTag),
                  if (liveTag != null || showPracticeTag) SizedBox(height: gap),
                  AnimatedSwitcher(
                    duration: NuvoMotion.springDuration,
                    switchInCurve: NuvoMotion.spring,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    child: SizedBox(
                      key: ValueKey(title),
                      width: double.infinity,
                      child: Text(
                        title,
                        style: V13.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: V13.bodyStrong),
                  ],
                  if (footer != null) ...[
                    SizedBox(height: compact ? V13.gapMd : V13.gapLg),
                    footer!,
                  ],
                  if (racers > 0) ...[
                    SizedBox(height: compact ? V13.gapMd : V13.gapLg),
                    _Lane(racers: racers, size: compact ? 36 : 44),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Lane extends StatelessWidget {
  const _Lane({required this.racers, required this.size});

  final int racers;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < racers; i++) ...[
          if (i > 0) const SizedBox(width: V13.gapSm),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: V13.card,
              shape: BoxShape.circle,
              border: Border.all(
                color: i == 0 ? V13.blue : V13.navy,
                width: V13.outlineThick,
              ),
            ),
            child: Icon(
              Icons.person_rounded,
              color: V13.muted,
              size: size * .6,
            ),
          ),
        ],
        Expanded(
          child: Container(
            height: 2.5,
            margin: const EdgeInsets.symmetric(horizontal: V13.gapSm),
            color: V13.navy.withValues(alpha: .35),
          ),
        ),
        const Icon(Icons.flag_rounded, color: V13.navy, size: 28),
      ],
    );
  }
}
