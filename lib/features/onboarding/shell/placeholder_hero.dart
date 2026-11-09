import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_step.dart';

/// Part-0 stand-in for a step's real hero (Parts A–F replace it). Renders
/// a v13-styled card tinted with the step's palette color and its S-number,
/// wrapped in [NuvoFloat] so the float plumbing is exercised end-to-end.
class ObPlaceholderHero extends StatelessWidget {
  const ObPlaceholderHero({
    super.key,
    required this.step,
    this.color = V13.sky,
    this.label,
  });

  final OnboardingStep step;
  final Color color;

  /// Short caption on the card (defaults to the step's S-number).
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: NuvoFloat(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(V13.radiusCardLg),
            border: Border.all(color: V13.navy, width: V13.outlineThick),
            boxShadow: V13.shadow6,
          ),
          padding: const EdgeInsets.all(V13.gapXxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.directions_run_rounded,
                size: 56,
                color: V13.navy,
              ),
              const SizedBox(height: V13.gapMd),
              Text(
                label ?? 'S${step.index}',
                style: V13.sectionHead,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
