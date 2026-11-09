import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S8 — Q1 "What do you want to race?" Part C replaces the chips with the
/// real pick grid; answers persist via [OnboardingFlowController.setAnswer]
/// and seed the seeded-race name.
class ObQuestionsOneStep extends ConsumerStatefulWidget {
  const ObQuestionsOneStep({super.key});

  @override
  ConsumerState<ObQuestionsOneStep> createState() => _ObQuestionsOneStepState();
}

class _ObQuestionsOneStepState extends ConsumerState<ObQuestionsOneStep> {
  String? _picked;

  static const _options = [
    ObCopy.q1Fitness,
    ObCopy.q1Running,
    ObCopy.q1Reading,
    ObCopy.q1Studying,
    ObCopy.q1Gaming,
    ObCopy.q1Other,
  ];

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.questions1,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.questions1,
        color: V13.mint,
      ),
      title: ObCopy.questionsTitle1,
      subtitle: ObCopy.questionsSub,
      body: Wrap(
        spacing: V13.gapSm,
        runSpacing: V13.gapSm,
        children: [
          for (final o in _options)
            ChoiceChip(
              label: Text(o),
              selected: _picked == o,
              onSelected: (_) {
                setState(() => _picked = o);
                flow.setAnswer(1, o);
              },
            ),
        ],
      ),
      ctaLabel: ObCopy.next,
      onCta: () => obAdvance(context, ref, OnboardingStep.questions1),
      onBack: flow.goBack,
      onSkip: flow.skipQuestions,
    );
  }
}
