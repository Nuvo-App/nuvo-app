import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../../core/v13/widgets/v13_confetti.dart';
import '../../../core/v13/widgets/v13_face.dart';
import '../../../core/v13/widgets/v13_number_pop.dart';
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';

/// S3 — "Climb the board." A live leaderboard card whose rows tick points
/// up on [NuvoMotion.boardTick]; the user's row starts 4th and the script
/// pushes it up a rank each tick until the gold-ring flash + confetti at
/// 1st (spec). "Create my player" heads into sign-up; "I already have an
/// account" heads into sign-in — both complete the intros.
class ObIntroBoardStep extends ConsumerStatefulWidget {
  const ObIntroBoardStep({super.key});

  @override
  ConsumerState<ObIntroBoardStep> createState() => _ObIntroBoardStepState();
}

class _ObIntroBoardStepState extends ConsumerState<ObIntroBoardStep> {
  /// One leaderboard row's mutable standing — instance state so a
  /// goBack-remount replays the climb from 4th, not a dead board.
  final List<_Row> _rows = [
    _Row(name: 'Maya', points: 68),
    _Row(name: 'Leo', points: 54),
    _Row(name: 'Sam', points: 41),
    _Row(name: ObCopy.you, points: 24, isMe: true),
  ];

  /// The user's scripted points gain per tick — lands on 1st in three
  /// ticks (~7 s), while friends drift a little for the "live" feel.
  static const int _meGain = 18;
  static const List<int> _botDrift = [2, 1, 2];

  Timer? _ticker;
  bool _crowned = false;

  /// Current ranks — rows sorted by points, descending.
  List<_Row> get _standings {
    final s = [..._rows]
      ..sort((a, b) => b.points.compareTo(a.points));
    return s;
  }

  void _tick(Timer _) {
    setState(() {
      var bot = 0;
      for (final row in _rows) {
        row.points += row.isMe ? _meGain : _botDrift[bot++ % _botDrift.length];
      }
      if (_standings.first.isMe) _crowned = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(NuvoMotion.boardTick, _tick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _join(AuthIntent intent) {
    ref.read(authIntentProvider.notifier).state = intent;
    obAdvance(context, ref, OnboardingStep.introBoard);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.introBoard,
      hero: _BoardCard(standings: _standings, crowned: _crowned),
      title: ObCopy.introBoardTitle,
      subtitle: ObCopy.introBoardSub,
      body: Center(
        child: NuvoPressable(
          onTap: () => _join(AuthIntent.signIn),
          semanticLabel: ObCopy.introBoardLogin,
          child: Padding(
            padding: const EdgeInsets.all(V13.gapSm),
            child: Text(
              ObCopy.introBoardLogin,
              style: V13.bodyStrong.copyWith(
                color: V13.blue,
                decoration: TextDecoration.underline,
                decorationColor: V13.blue,
              ),
            ),
          ),
        ),
      ),
      ctaLabel: ObCopy.introBoardCta,
      onCta: () => _join(AuthIntent.signUp),
      onBack: flow.goBack,
      onSkip: flow.skipIntros,
    );
  }
}

class _Row {
  _Row({required this.name, required this.points, this.isMe = false});

  final String name;
  int points;
  final bool isMe;
}

/// The leaderboard card — four rows reordering under the spring, the
/// confetti once the user's row takes 1st.
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.standings, required this.crowned});

  final List<_Row> standings;
  final bool crowned;

  static const double _rowH = 52;
  static const double _rowGap = 8;

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    final radius = BorderRadius.circular(V13.radiusCardLg);
    return Center(
      child: Container(
        key: const ValueKey('ob-board-card'),
        height: 300,
        decoration: BoxDecoration(
          color: V13.card,
          borderRadius: radius,
          border: Border.all(color: V13.navy, width: V13.outlineThick),
          boxShadow: V13.shadow6,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              top: V13.gapLg,
              left: V13.gapLg,
              right: V13.gapLg,
              child: Stack(
                children: [
                  for (final row in standings)
                    AnimatedPositioned(
                      key: ValueKey(row.name),
                      top: standings.indexOf(row) * (_rowH + _rowGap),
                      left: 0,
                      right: 0,
                      height: _rowH,
                      duration:
                          reduce ? Duration.zero : NuvoMotion.springDuration,
                      curve: NuvoMotion.spring,
                      child: _BoardRow(
                        row: row,
                        rank: standings.indexOf(row) + 1,
                        crowned: crowned && row.isMe,
                      ),
                    ),
                ],
              ),
            ),
            if (crowned)
              const Positioned.fill(
                child: IgnorePointer(
                  child: V13Confetti(
                    particleCount: NuvoMotion.confettiPieces ~/ 2,
                    duration: NuvoMotion.confetti,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One leaderboard row — rank pop, silhouette face, name, points.
class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.row,
    required this.rank,
    required this.crowned,
  });

  final _Row row;
  final int rank;
  final bool crowned;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: V13.gapMd),
      decoration: BoxDecoration(
        color: row.isMe ? V13.sky : V13.card,
        borderRadius: BorderRadius.circular(V13.radiusCardLg - 10),
        border: Border.all(
          color: V13.navy,
          width: row.isMe ? V13.outlineThick : V13.outline,
        ),
        boxShadow: row.isMe ? V13.hardShadow(x: 2, y: 2) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: V13NumberPop(value: rank, style: V13.numberSm),
          ),
          const SizedBox(width: V13.gapSm),
          _CrownRing(active: crowned, child: V13Face(size: 34, isMe: row.isMe)),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Text(
              row.isMe ? ObCopy.you : row.name,
              style: V13.bodyStrong,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          V13NumberPop(value: row.points, style: V13.numberSm),
        ],
      ),
    );
  }
}

/// The gold ring flash once the user's row takes 1st — a one-shot halo
/// around the face (expands, fades, gone).
class _CrownRing extends StatelessWidget {
  const _CrownRing({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        if (active)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: NuvoMotion.springDuration,
            curve: NuvoMotion.spring,
            builder: (context, t, _) => Container(
              width: 34 + 10 * t,
              height: 34 + 10 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: V13.sun.withValues(alpha: 1 - t * 0.4),
                  width: V13.outlineThick,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
