import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S14 — Tour stop 2: Crew (My Nuvo code open + share). Part E mounts the
/// real overlay; the stub walks the stop (+10).
class ObTourCrewStep extends ConsumerStatefulWidget {
  const ObTourCrewStep({super.key});

  @override
  ConsumerState<ObTourCrewStep> createState() => _ObTourCrewStepState();
}

class _ObTourCrewStepState extends ConsumerState<ObTourCrewStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(onboardingFlowProvider.notifier)
          .tourStopViewed(OnboardingStep.tourCrew);
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.tourCrew,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.tourCrew,
        color: V13.lilac,
        label: 'Crew',
      ),
      title: ObCopy.tourCrewText,
      subtitle: ObCopy.tourCounter(2),
      body: Text(
        ObCopy.tourCrewBubble,
        style: V13.body.copyWith(color: V13.muted),
      ),
      ctaLabel: ObCopy.tourCrewShare,
      onCta: () => obAdvance(context, ref, OnboardingStep.tourCrew),
      onSkip: flow.skipTour,
      skipLabel: ObCopy.skipTour,
    );
  }
}
