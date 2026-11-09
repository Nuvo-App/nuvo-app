import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S1 — "Race anything." Part A replaces the hero with the tap-duel race
/// card and the win moment; the stub walks the step.
class ObIntroRaceStep extends ConsumerWidget {
  const ObIntroRaceStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.introRace,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.introRace,
        color: V13.coral,
      ),
      title: ObCopy.introRaceTitle,
      subtitle: ObCopy.introRaceSub,
      ctaLabel: ObCopy.next,
      onCta: () => obAdvance(context, ref, OnboardingStep.introRace),
      onSkip: flow.skipIntros,
    );
  }
}
