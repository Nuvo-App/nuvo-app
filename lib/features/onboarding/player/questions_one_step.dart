import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/v13.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import 'race_preview.dart';

/// S8 Q1 — "What do you want to race?" Six outlined chips (2 columns, 56px),
/// single choice; the hero race card rewrites its title live. The answer is
/// persisted through [OnboardingFlowController.setAnswer] and seeds the S9
/// practice race. Skippable (pays the +10 starter-questions award anyway).
class ObQuestionsOneStep extends ConsumerWidget {
  const ObQuestionsOneStep({super.key});

  static const options = [
    (ObCopy.q1Fitness, Icons.fitness_center_rounded),
    (ObCopy.q1Running, Icons.directions_run_rounded),
    (ObCopy.q1Reading, Icons.menu_book_rounded),
    (ObCopy.q1Studying, Icons.school_rounded),
    (ObCopy.q1Gaming, Icons.sports_esports_rounded),
    (ObCopy.q1Other, Icons.more_horiz_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(onboardingFlowProvider.select((s) => s.answerQ1));
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.questions1,
      hero: ObRacePreviewCard(
        title: obRacePreviewTitle(picked),
        color: V13.mint,
      ),
      title: ObCopy.questionsTitle1,
      subtitle: ObCopy.questionsSub,
      body: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: V13.gapMd,
        crossAxisSpacing: V13.gapMd,
        mainAxisExtent: 56,
        childAspectRatio: 1,
        children: [
          for (final (label, icon) in options)
            _PickChip(
              label: label,
              icon: icon,
              selected: picked == label,
              onTap: () {
                NuvoHaptics.select();
                flow.setAnswer(1, label);
              },
            ),
        ],
      ),
      ctaLabel: ObCopy.next,
      ctaEnabled: picked != null,
      onCta: () => obAdvance(context, ref, OnboardingStep.questions1),
      onBack: flow.goBack,
      onSkip: flow.skipQuestions,
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V13.radiusButton),
      shadow: V13.shadow3,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: NuvoMotion.springDuration,
        curve: NuvoMotion.spring,
        padding: const EdgeInsets.symmetric(horizontal: V13.gapMd),
        decoration: BoxDecoration(
          color: selected ? V13.blue.withValues(alpha: .14) : V13.card,
          borderRadius: BorderRadius.circular(V13.radiusButton),
          border: Border.all(
            color: selected ? V13.blue : V13.navy,
            width: V13.outlineThick,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: selected ? V13.blue : V13.navy),
            const SizedBox(width: V13.gapSm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: V13.bodyStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
