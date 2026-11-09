import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S13 — Tour stop 1: Compete. Part E mounts the real [TourEngine]
/// overlay on the actual Compete screen; the stub walks the stop (Join →
/// +10) and reports it viewed.
class ObTourCompeteStep extends ConsumerStatefulWidget {
  const ObTourCompeteStep({super.key});

  @override
  ConsumerState<ObTourCompeteStep> createState() => _ObTourCompeteStepState();
}

class _ObTourCompeteStepState extends ConsumerState<ObTourCompeteStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(onboardingFlowProvider.notifier)
          .tourStopViewed(OnboardingStep.tourCompete);
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.tourCompete,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.tourCompete,
        color: V13.mint,
        label: 'Compete',
      ),
      title: ObCopy.tourCompeteText,
      subtitle: ObCopy.tourCounter(1),
      body: Text(
        ObCopy.tourCompeteMission,
        style: V13.body.copyWith(color: V13.muted),
      ),
      ctaLabel: ObCopy.tourCompeteJoin,
      onCta: () => obAdvance(context, ref, OnboardingStep.tourCompete),
      onSkip: flow.skipTour,
      skipLabel: ObCopy.skipTour,
    );
  }
}
