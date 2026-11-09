import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/onboarding_shell_controller.dart';
import '../shell/placeholder_hero.dart';

/// S11 — Arena tour: the practice race + first proof. Part D drives the
/// real Submit-proof sheet and camera path; the stub offers both
/// resolutions (+30 verified, +10 camera fallback).
class ObArenaTourStep extends ConsumerWidget {
  const ObArenaTourStep({super.key});

  Future<void> _proof(
    BuildContext context,
    WidgetRef ref, {
    required bool fallback,
  }) async {
    final shell = OnboardingShellScope.of(context);
    final flow = ref.read(onboardingFlowProvider.notifier);
    flow.proofStarted();
    final awarded = await flow.proofCompleted(cameraFallback: fallback);
    if (awarded > 0) shell.award(awarded);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OnboardingShell(
      step: OnboardingStep.arenaTour,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.arenaTour,
        color: V13.coral,
        label: ObCopy.practiceTag,
      ),
      title: ObCopy.arenaTourCoach,
      subtitle: ObCopy.arenaTourCameraReason,
      body: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _proof(context, ref, fallback: true),
          child: Text(
            ObCopy.arenaTourSkipCamera,
            style: V13.bodyStrong.copyWith(color: V13.muted),
          ),
        ),
      ),
      ctaLabel: 'Submit proof',
      onCta: () => _proof(context, ref, fallback: false),
    );
  }
}
