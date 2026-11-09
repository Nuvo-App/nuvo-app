import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/onboarding_shell_controller.dart';
import '../shell/placeholder_hero.dart';

/// S12 — Notification opt-in in context. Part E wires the real OS prompt;
/// the stub resolves the outcome the way the real one will ('accepted'
/// pays +5, 'declined' pays nothing).
class ObNotifyOptInStep extends ConsumerWidget {
  const ObNotifyOptInStep({super.key});

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref, {
    required bool accepted,
  }) async {
    final shell = OnboardingShellScope.of(context);
    final flow = ref.read(onboardingFlowProvider.notifier);
    await flow.setNotifyOutcome(accepted ? 'accepted' : 'declined');
    final awarded = await flow.completeStep(OnboardingStep.notifyOptIn);
    if (awarded > 0) shell.award(awarded);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OnboardingShell(
      step: OnboardingStep.notifyOptIn,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.notifyOptIn,
        color: V13.sky,
        label: 'Buzz',
      ),
      title: ObCopy.notifyTitle,
      body: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _resolve(context, ref, accepted: false),
          child: Text(
            ObCopy.notifyLater,
            style: V13.bodyStrong.copyWith(color: V13.muted),
          ),
        ),
      ),
      ctaLabel: ObCopy.notifyCta,
      onCta: () => _resolve(context, ref, accepted: true),
    );
  }
}
