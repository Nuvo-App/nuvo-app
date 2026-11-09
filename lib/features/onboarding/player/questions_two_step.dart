import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/v13.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import 'race_preview.dart';

/// S8 Q2 — "Race solo or with friends?" Three big cards. "With friends"
/// adds the QR share step in the tour; "Solo first" skips it. Completing or
/// skipping pays the +10 starter-questions award.
class ObQuestionsTwoStep extends ConsumerWidget {
  const ObQuestionsTwoStep({super.key});

  static const options = [
    (ObCopy.q2WithFriends, 'Invite a friend with your Nuvo code.',
        Icons.group_rounded),
    (ObCopy.q2Solo, 'Practice alone, add friends later.',
        Icons.person_rounded),
    (ObCopy.q2Surprise, 'We pick a good start for you.',
        Icons.auto_awesome_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q1 = ref.watch(onboardingFlowProvider.select((s) => s.answerQ1));
    final picked = ref.watch(onboardingFlowProvider.select((s) => s.answerQ2));
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.questions2,
      hero: ObRacePreviewCard(
        title: obRacePreviewTitle(q1),
        color: V13.lilac,
        racers: picked == ObCopy.q2Solo ? 1 : 3,
      ),
      title: ObCopy.questionsTitle2,
      subtitle: ObCopy.questionsSub,
      body: Column(
        children: [
          for (final (label, sub, icon) in options) ...[
            _ChoiceCard(
              label: label,
              sub: sub,
              icon: icon,
              selected: picked == label,
              onTap: () {
                NuvoHaptics.select();
                flow.setAnswer(2, label);
              },
            ),
            const SizedBox(height: V13.gapMd),
          ],
        ],
      ),
      ctaLabel: ObCopy.next,
      ctaEnabled: picked != null,
      onCta: () => obAdvance(context, ref, OnboardingStep.questions2),
      onBack: flow.goBack,
      onSkip: flow.skipQuestions,
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V13.radiusCard),
      shadow: V13.shadow4,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: NuvoMotion.springDuration,
        curve: NuvoMotion.spring,
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.all(V13.gapLg),
        decoration: BoxDecoration(
          color: selected ? V13.blue.withValues(alpha: .14) : V13.card,
          borderRadius: BorderRadius.circular(V13.radiusCard),
          border: Border.all(
            color: selected ? V13.blue : V13.navy,
            width: V13.outlineThick,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: selected ? V13.blue : V13.navy),
            const SizedBox(width: V13.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: V13.cardTitle),
                  Text(sub, style: V13.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
