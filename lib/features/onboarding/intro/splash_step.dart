import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S0 — splash. Part A owns the real splash→flow handoff; the stub holds
/// the wordmark for [NuvoMotion.splashHold] then hands S1 the stage.
class ObSplashStep extends ConsumerStatefulWidget {
  const ObSplashStep({super.key});

  @override
  ConsumerState<ObSplashStep> createState() => _ObSplashStepState();
}

class _ObSplashStepState extends ConsumerState<ObSplashStep> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(NuvoMotion.splashHold, _advance);
  }

  void _advance() {
    if (_done) return;
    _done = true;
    ref
        .read(onboardingFlowProvider.notifier)
        .completeStep(OnboardingStep.splash);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: OnboardingStep.splash,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.splash,
        color: V13.sky,
        label: 'Nuvo',
      ),
      title: 'Nuvo',
      subtitle: 'Part 0 stub — the real splash lands in Part A.',
      ctaLabel: 'Next',
      onCta: _advance,
    );
  }
}
