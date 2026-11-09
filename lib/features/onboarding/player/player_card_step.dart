import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S7 — Player card. Part C builds the real card (name, @username with
/// availability check, photo, 13+/terms checkbox); the stub carries the
/// +15 award so the rail can be watched filling.
class ObPlayerCardStep extends ConsumerWidget {
  const ObPlayerCardStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OnboardingShell(
      step: OnboardingStep.playerCard,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.playerCard,
        color: V13.coral,
        label: ObCopy.playerPassLabel,
      ),
      title: ObCopy.playerCardStepCounter,
      subtitle: ObCopy.playerCardNameWhy,
      ctaLabel: ObCopy.playerCardCta,
      onCta: () => obAdvance(context, ref, OnboardingStep.playerCard),
    );
  }
}
