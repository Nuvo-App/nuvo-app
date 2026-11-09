import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/v13.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import 'race_preview.dart';

/// S9 — "Your first race is ready." A 2.2s no-input transition: "Building
/// your first race..." then "Practice race vs Nuvo Crew is live" while the
/// three racer cards deal in. The seeded race name comes from the Q1 answer
/// (stored by the flow controller). Advances by itself; the CTA only skips
/// ahead — it is never a trap.
class ObFirstRaceReadyStep extends ConsumerStatefulWidget {
  const ObFirstRaceReadyStep({super.key});

  @override
  ConsumerState<ObFirstRaceReadyStep> createState() =>
      _ObFirstRaceReadyStepState();
}

class _ObFirstRaceReadyStepState extends ConsumerState<ObFirstRaceReadyStep> {
  Timer? _phase;
  Timer? _done;
  bool _live = false;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _phase = Timer(NuvoMotion.firstRaceTransition ~/ 2, () {
      if (mounted) setState(() => _live = true);
    });
    _done = Timer(NuvoMotion.firstRaceTransition, _advance);
  }

  @override
  void dispose() {
    _phase?.cancel();
    _done?.cancel();
    super.dispose();
  }

  Future<void> _advance() async {
    if (_advanced || !mounted) return;
    _advanced = true;
    _phase?.cancel();
    _done?.cancel();
    await obAdvance(context, ref, OnboardingStep.firstRaceReady);
  }

  @override
  Widget build(BuildContext context) {
    final q1 = ref.watch(onboardingFlowProvider.select((s) => s.answerQ1));
    return OnboardingShell(
      step: OnboardingStep.firstRaceReady,
      hero: ObRacePreviewCard(
        title: obRacePreviewTitle(q1),
        subtitle: ObCopy.practiceRaceName(obRaceActivity(q1)).split(' · ').last,
        color: V13.coral,
      ),
      title: _live ? ObCopy.firstRaceLive : ObCopy.firstRaceBuilding,
      subtitle: obPracticeRaceName(q1),
      body: const Column(
        children: [
          NuvoEnter(
            index: 0,
            child: _RacerRow(name: ObCopy.nuvoCrew, score: 6, rank: '1st'),
          ),
          SizedBox(height: V13.gapSm),
          NuvoEnter(
            index: 1,
            child: _RacerRow(name: ObCopy.nuvoCrew, score: 4, rank: '2nd'),
          ),
          SizedBox(height: V13.gapSm),
          NuvoEnter(
            index: 2,
            child: _RacerRow(
              name: ObCopy.you,
              score: 0,
              rank: '3rd',
              isYou: true,
            ),
          ),
        ],
      ),
      ctaLabel: ObCopy.next,
      onCta: _advance,
    );
  }
}

class _RacerRow extends StatelessWidget {
  const _RacerRow({
    required this.name,
    required this.score,
    required this.rank,
    this.isYou = false,
  });

  final String name;
  final int score;
  final String rank;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: V13.gapMd),
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusButton),
        border: Border.all(
          color: isYou ? V13.blue : V13.navy,
          width: V13.outlineThick,
        ),
        boxShadow: V13.shadow3,
      ),
      child: Row(
        children: [
          Text(rank, style: V13.bodyStrong.copyWith(color: V13.muted)),
          const SizedBox(width: V13.gapMd),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: V13.bg,
              shape: BoxShape.circle,
              border: Border.all(color: V13.navy, width: V13.outline),
            ),
            child: const Icon(Icons.person_rounded, size: 20, color: V13.muted),
          ),
          const SizedBox(width: V13.gapMd),
          Expanded(child: Text(name, style: V13.bodyStrong)),
          Text('$score', style: V13.cardTitle),
        ],
      ),
    );
  }
}
