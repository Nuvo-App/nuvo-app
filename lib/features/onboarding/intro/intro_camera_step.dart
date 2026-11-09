import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S2 — "Prove it on camera." Part A replaces the hero with the skeleton
/// over-camera silhouette and the "AI Motion verified" pill.
class ObIntroCameraStep extends ConsumerWidget {
  const ObIntroCameraStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.introCamera,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.introCamera,
        color: V13.lilac,
      ),
      title: ObCopy.introCameraTitle,
      subtitle: ObCopy.introCameraSub,
      ctaLabel: ObCopy.next,
      onCta: () => obAdvance(context, ref, OnboardingStep.introCamera),
      onBack: flow.goBack,
      onSkip: flow.skipIntros,
    );
  }
}
