import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S4 — "Save your spot." Part B wires the real Apple / Google / email
/// sign-in rows to the existing auth controller (no auth data-layer
/// changes); the stub advances so the rest of the flow is walkable.
class ObSignInStep extends ConsumerWidget {
  const ObSignInStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OnboardingShell(
      step: OnboardingStep.signIn,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.signIn,
        color: V13.mint,
      ),
      title: ObCopy.signInTitle,
      subtitle: ObCopy.signInSub,
      ctaLabel: ObCopy.signInEmailLink,
      onCta: () => obAdvance(context, ref, OnboardingStep.signIn),
    );
  }
}
