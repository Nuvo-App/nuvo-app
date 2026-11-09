import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S5 — "What's your email?" Part B replaces this with the player-pass
/// ticket (dead-zone fix: field autofocused, CTA live on any valid input,
/// error inline under the field).
class ObEmailStep extends ConsumerStatefulWidget {
  const ObEmailStep({super.key});

  @override
  ConsumerState<ObEmailStep> createState() => _ObEmailStepState();
}

class _ObEmailStepState extends ConsumerState<ObEmailStep> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final typed = _ctrl.text.trim();
    await flow.setEmail(typed.isEmpty ? null : typed);
    if (!mounted) return;
    await obAdvance(context, ref, OnboardingStep.email);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.email,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.email,
        color: V13.sky,
        label: ObCopy.playerPassLabel,
      ),
      title: ObCopy.emailTitle,
      subtitle: ObCopy.emailSub,
      body: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: ObCopy.emailFieldLabel),
      ),
      ctaLabel: ObCopy.emailCta,
      onCta: _send,
      onBack: flow.goBack,
    );
  }
}
