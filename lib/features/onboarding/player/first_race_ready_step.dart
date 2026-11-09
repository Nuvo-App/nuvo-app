import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S10 — "Your first race is ready." Part D turns this into the seeded
/// practice-race reveal (the name comes from the Q1 answer); the stub
/// carries the step's XP award.
class ObFirstRaceReadyStep extends ConsumerWidget {
  const ObFirstRaceReadyStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(
      onboardingFlowProvider.select((s) => s.answerQ1),
    );
    return OnboardingShell(
      step: OnboardingStep.firstRaceReady,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.firstRaceReady,
        color: V13.sun,
        label: ObCopy.practiceTag,
      ),
      title: ObCopy.firstRaceLive,
      subtitle: ObCopy.practiceRaceName(activity ?? 'Fitness'),
      ctaLabel: ObCopy.next,
      onCta: () => obAdvance(context, ref, OnboardingStep.firstRaceReady),
    );
  }
}
