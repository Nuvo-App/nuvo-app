import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S15 — Tour stop 3: Profile (first badge tile). Part E mounts the real
/// overlay; the stub walks the stop (+5).
class ObTourProfileStep extends ConsumerStatefulWidget {
  const ObTourProfileStep({super.key});

  @override
  ConsumerState<ObTourProfileStep> createState() => _ObTourProfileStepState();
}

class _ObTourProfileStepState extends ConsumerState<ObTourProfileStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(onboardingFlowProvider.notifier)
          .tourStopViewed(OnboardingStep.tourProfile);
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.tourProfile,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.tourProfile,
        color: V13.sun,
        label: 'Profile',
      ),
      title: ObCopy.tourProfileText,
      subtitle: ObCopy.tourCounter(3),
      body: Text(ObCopy.tourDone, style: V13.body.copyWith(color: V13.muted)),
      ctaLabel: ObCopy.next,
      onCta: () => obAdvance(context, ref, OnboardingStep.tourProfile),
      onSkip: flow.skipTour,
      skipLabel: ObCopy.skipTour,
    );
  }
}
