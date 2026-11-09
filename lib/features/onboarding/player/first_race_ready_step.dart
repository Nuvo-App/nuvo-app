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
/// ahead — it is never a trap. The hero is the race card (no duplicate
/// racer tokens), a progress bar fills while it builds, and the standings
/// deal in one by one so the screen never sits empty.
class ObFirstRaceReadyStep extends ConsumerStatefulWidget {
  const ObFirstRaceReadyStep({super.key});

  @override
  ConsumerState<ObFirstRaceReadyStep> createState() =>
      _ObFirstRaceReadyStepState();
}

class _ObFirstRaceReadyStepState extends ConsumerState<ObFirstRaceReadyStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: NuvoMotion.firstRaceTransition,
  );
  Timer? _phase;
  Timer? _done;
  bool _live = false;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _progress.forward();
    _phase = Timer(NuvoMotion.firstRaceTransition ~/ 2, () {
      if (!mounted) return;
      NuvoHaptics.light();
      setState(() => _live = true);
    });
    _done = Timer(NuvoMotion.firstRaceTransition, _advance);
  }

  @override
  void dispose() {
    _phase?.cancel();
    _done?.cancel();
    _progress.dispose();
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
    final lead = NuvoMotion.firstRaceTransition ~/ 5;
    return OnboardingShell(
      step: OnboardingStep.firstRaceReady,
      heroHeight: obHeroHeight(context, tall: 190, small: 150),
      hero: ObRacePreviewCard(
        title: obRacePreviewTitle(q1),
        subtitle: ObCopy.practiceRaceName(obRaceActivity(q1)).split(' · ').last,
        color: V13.coral,
        racers: 0,
        footer: _BuildBar(progress: _progress),
        liveTag: AnimatedSwitcher(
          duration: NuvoMotion.springDuration,
          switchInCurve: NuvoMotion.spring,
          layoutBuilder: (cur, prev) =>
              Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
          child: V13Pill(
            key: ValueKey(_live),
            label: _live ? 'Live' : ObCopy.practiceTag,
            color: _live ? V13.mint : V13.card,
          ),
        ),
      ),
      title: _live ? ObCopy.firstRaceLive : ObCopy.firstRaceBuilding,
      body: Column(
        spacing: V13.gapSm,
        children: [
          _Deal(
            delay: lead,
            child: const _RacerRow(
              name: ObCopy.nuvoCrew,
              score: 6,
              rank: '1st',
            ),
          ),
          _Deal(
            delay: lead + NuvoMotion.staggerStep * 2,
            child: const _RacerRow(
              name: ObCopy.nuvoCrew,
              score: 4,
              rank: '2nd',
            ),
          ),
          _Deal(
            delay: lead + NuvoMotion.staggerStep * 4,
            child: const _RacerRow(
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

/// Thin outlined bar that fills over the build window.
class _BuildBar extends StatelessWidget {
  const _BuildBar({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: progress,
        builder: (_, _) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress.value,
            heightFactor: 1,
            child: const ColoredBox(color: V13.blue),
          ),
        ),
      ),
    );
  }
}

/// Deals a child in like a card: rises, un-tilts and fades, after [delay].
class _Deal extends StatefulWidget {
  const _Deal({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_Deal> createState() => _DealState();
}

class _DealState extends State<_Deal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.enter,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (_, child) {
        final raw = _ctrl.value.clamp(0.0, 1.0);
        final t = reduce ? raw : NuvoMotion.spring.transform(raw);
        return Opacity(
          opacity: raw.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, reduce ? 0 : NuvoMotion.enterOffsetY * (1 - t)),
            child: Transform.rotate(
              angle: reduce ? 0 : -0.06 * (1 - t),
              child: child,
            ),
          ),
        );
      },
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
      height: MediaQuery.sizeOf(context).height < 700 ? 48 : 56,
      padding: const EdgeInsets.symmetric(horizontal: V13.gapMd),
      decoration: BoxDecoration(
        color: isYou ? obSelectedFill : V13.card,
        borderRadius: BorderRadius.circular(V13.radiusButton),
        border: Border.all(
          color: isYou ? V13.blue : V13.navy,
          width: V13.outlineThick,
        ),
        boxShadow: V13.shadow3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              rank,
              style: V13.bodyStrong.copyWith(
                color: isYou ? V13.blue : V13.muted,
              ),
            ),
          ),
          const SizedBox(width: V13.gapSm),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: V13.bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: isYou ? V13.blue : V13.navy,
                width: V13.outline,
              ),
            ),
            child: const Icon(Icons.person_rounded, size: 20, color: V13.muted),
          ),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: V13.bodyStrong,
            ),
          ),
          Text('$score', style: V13.cardTitle),
        ],
      ),
    );
  }
}
