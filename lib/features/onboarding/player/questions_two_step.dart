import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S9 — Q2 "Race solo or with friends?" Completing (or skipping) pays the
/// +10 starter-questions award.
class ObQuestionsTwoStep extends ConsumerStatefulWidget {
  const ObQuestionsTwoStep({super.key});

  @override
  ConsumerState<ObQuestionsTwoStep> createState() => _ObQuestionsTwoStepState();
}

class _ObQuestionsTwoStepState extends ConsumerState<ObQuestionsTwoStep> {
  String? _picked;

  static const _options = [
    ObCopy.q2WithFriends,
    ObCopy.q2Solo,
    ObCopy.q2Surprise,
  ];

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.questions2,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.questions2,
        color: V13.lilac,
      ),
      title: ObCopy.questionsTitle2,
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
                flow.setAnswer(2, o);
              },
            ),
        ],
      ),
      ctaLabel: ObCopy.next,
      onCta: () => obAdvance(context, ref, OnboardingStep.questions2),
      onBack: flow.goBack,
      onSkip: flow.skipQuestions,
    );
  }
}
