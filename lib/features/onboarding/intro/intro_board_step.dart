import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S3 — "Climb the board." Part A replaces the hero with the leaderboard
/// card fan and the live "you move up" moment.
class ObIntroBoardStep extends ConsumerWidget {
  const ObIntroBoardStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.introBoard,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.introBoard,
        color: V13.sun,
      ),
      title: ObCopy.introBoardTitle,
      subtitle: ObCopy.introBoardSub,
      ctaLabel: ObCopy.introBoardCta,
      onCta: () => obAdvance(context, ref, OnboardingStep.introBoard),
      onBack: flow.goBack,
      onSkip: flow.skipIntros,
    );
  }
}
