import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S6 — "Check your email." Part B replaces this with the six code boxes,
/// the stamp moment and the resend row. First XP-awarding step in the flow
/// (+10 verified).
class ObCodeStep extends ConsumerWidget {
  const ObCodeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final email = ref.watch(onboardingFlowProvider.select((s) => s.email));
    return OnboardingShell(
      step: OnboardingStep.code,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.code,
        color: V13.mint,
        label: '6 digit code',
      ),
      title: ObCopy.codeTitle,
      subtitle: ObCopy.codeSub,
      body: Text(ObCopy.codeSentTo(email ?? 'your email'), style: V13.caption),
      ctaLabel: 'Verify',
      onCta: () => obAdvance(context, ref, OnboardingStep.code),
      onBack: flow.goBack,
    );
  }
}
