import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../../core/v13/widgets/v13_confetti.dart';
import '../../../core/v13/widgets/v13_face.dart';
import '../../../core/v13/widgets/v13_number_pop.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';

/// S1 — "Race anything." The tap duel: a coral hero card holding a mini
/// lane where each tap advances your token one bead for 5 s. Two Nuvo
/// Crew ghost tokens creep ahead early, then the script concedes — the
/// user always wins by 1–2 beads at the last second (spec: "never lose").
///
/// Next is pressable at any time: pressed early, the duel auto-plays a
/// scripted win over [NuvoMotion.duelAutoPlay] then hands S2 the stage.
class ObIntroRaceStep extends ConsumerStatefulWidget {
  const ObIntroRaceStep({super.key});

  @override
  ConsumerState<ObIntroRaceStep> createState() => _ObIntroRaceStepState();
}

class _ObIntroRaceStepState extends ConsumerState<ObIntroRaceStep>
    with TickerProviderStateMixin {
  /// Bead positions on the lane (0 = start, [_lastBead] = finish).
  static const int _lastBead = 12;

  /// Ghosts' scripted early lead and final lag, in beads — ghost 1 leads by
  /// two and concedes to one back, ghost 2 leads by one and ends two back.
  static const _leads = [2.0, 1.0];
  static const _lags = [1.0, 2.0];

  /// Scripted taps the auto-play adds on top of whatever the user did.
  static const int _autoTaps = 13;

  /// Fraction of the window in which ghosts hold their lead before the
  /// script concedes them behind the user ("the last second").
  static const double _concedeFrom = 0.55;

  late final AnimationController _duel = AnimationController(
    vsync: this,
    duration: NuvoMotion.duelWindow,
  );
  late final AnimationController _auto = AnimationController(
    vsync: this,
    duration: NuvoMotion.duelAutoPlay,
  );

  Timer? _idleTimer;
  bool _showPointer = false;

  int _count = 0;
  int _autoBase = 0;
  bool _started = false;
  bool _ended = false;
  bool _advanced = false;

  /// Elapsed fraction of the race (auto-play reuses the same clock face).
  double get _t =>
      _auto.isAnimating || _auto.isCompleted ? _auto.value : _duel.value;

  /// Ghost [i]'s scripted bead — leads early, concedes behind the user at
  /// the end. [userBeads] is continuous during auto-play.
  double _ghostBead(int i, double userBeads) {
    final t = _t.clamp(0.0, 1.0);
    final concede =
        ((t - _concedeFrom) / (1 - _concedeFrom)).clamp(0.0, 1.0) *
        ((t - _concedeFrom) / (1 - _concedeFrom)).clamp(0.0, 1.0);
    final surge = _leads[i] + (-_lags[i] - _leads[i]) * concede;
    return (userBeads + surge).clamp(0.0, _lastBead.toDouble());
  }

  double get _userBeads {
    if (_auto.isAnimating || _auto.isCompleted) {
      final target = (_autoBase + _autoTaps).clamp(0, _lastBead).toDouble();
      final u = (_t / 0.8).clamp(0.0, 1.0);
      return _autoBase + (target - _autoBase) * u;
    }
    return _count.clamp(0, _lastBead).toDouble();
  }

  void _armIdlePointer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(NuvoMotion.pointerIdle, () {
      if (!mounted || _started || _ended) return;
      setState(() => _showPointer = true);
    });
  }

  @override
  void initState() {
    super.initState();
    _duel.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    _duel.addListener(_onRaceClock);
    _auto.addListener(_onRaceClock);
    _auto.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _finish();
      _advance();
    });
    _armIdlePointer();
  }

  void _onRaceClock() {
    if (!mounted) return;
    setState(() {
      if (_auto.isAnimating) {
        _count = math.max(_count, _userBeads.round());
      }
    });
  }

  /// A tap on the card — starts the 5 s window on first contact, then one
  /// bead per tap with the spec's tick + selectionClick.
  void _onCardTap() {
    if (_ended || _auto.isAnimating || _auto.isCompleted) return;
    if (!_started) {
      _started = true;
      _idleTimer?.cancel();
      _duel.forward();
    }
    setState(() => _count++);
    NuvoHaptics.select();
    ref.read(nuvoSoundsProvider).pressTick();
  }

  /// The duel resolves: flag drops, confetti, mediumImpact, the win chip.
  void _finish() {
    if (_ended) return;
    setState(() {
      _ended = true;
      _showPointer = false;
    });
    NuvoHaptics.medium();
  }

  Future<void> _advance() async {
    if (_advanced) return;
    _advanced = true;
    await obAdvance(context, ref, OnboardingStep.introRace);
  }

  /// Next — pressable any time. Early presses fast-forward the duel to its
  /// scripted win inside [NuvoMotion.duelAutoPlay] before advancing.
  void _onNext() {
    if (_advanced) return;
    if (_ended) {
      _advance();
      return;
    }
    if (_auto.isAnimating) return;
    _idleTimer?.cancel();
    setState(() {
      _autoBase = _count.clamp(0, _lastBead);
      _showPointer = false;
    });
    _duel.stop();
    _auto.forward();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _duel.dispose();
    _auto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: OnboardingStep.introRace,
      hero: _DuelCard(
        count: _count,
        userBeads: _userBeads,
        ghost1Beads: _ghostBead(0, _userBeads),
        ghost2Beads: _ghostBead(1, _userBeads),
        lastBead: _lastBead,
        ended: _ended,
        showPointer: _showPointer,
        onTap: _onCardTap,
      ),
      title: ObCopy.introRaceTitle,
      subtitle: ObCopy.introRaceSub,
      ctaLabel: ObCopy.next,
      onCta: _onNext,
      onSkip: () => ref.read(onboardingFlowProvider.notifier).skipIntros(),
    );
  }
}

/// The coral race card — lane, three racer tokens, the score, flag and
/// chips. The whole card is the tap surface.
class _DuelCard extends StatelessWidget {
  const _DuelCard({
    required this.count,
    required this.userBeads,
    required this.ghost1Beads,
    required this.ghost2Beads,
    required this.lastBead,
    required this.ended,
    required this.showPointer,
    required this.onTap,
  });

  final int count;
  final double userBeads;
  final double ghost1Beads;
  final double ghost2Beads;
  final int lastBead;
  final bool ended;
  final bool showPointer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(V13.radiusCardLg);
    return Center(
      child: NuvoPressable(
        onTap: onTap,
        borderRadius: radius,
        shadow: V13.shadow6,
        // The press sinks the card; the per-bead tick is fired by the
        // step (selectionClick + pressTick), not the pressable's light.
        haptic: false,
        semanticLabel: ObCopy.introRaceHint,
        child: Container(
          key: const ValueKey('ob-duel-card'),
          height: 300,
          decoration: BoxDecoration(
            color: V13.coral,
            borderRadius: radius,
            border: Border.all(color: V13.navy, width: V13.outlineThick),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final lane = _LaneGeometry(
                width: constraints.maxWidth,
                height: 150,
                lastBead: lastBead,
              );
              return Stack(
                children: [
                  Positioned(
                    top: V13.gapLg,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: V13NumberPop(
                        value: count,
                        style: V13.hugeNumber.copyWith(fontSize: 56),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 92,
                    height: lane.height,
                    child: _Lane(lane: lane, ended: ended),
                  ),
                  // Ghosts first so the user's token rides on top.
                  for (final (beads, dy, isYou) in [
                    (ghost2Beads, 22.0, false),
                    (ghost1Beads, 6.0, false),
                    (userBeads, -10.0, true),
                  ])
                    _Token(
                      lane: lane,
                      beads: beads,
                      laneOffset: dy,
                      isYou: isYou,
                      float: !isYou,
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: V13.gapLg,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: NuvoMotion.ctaFade,
                        child: _Chip(
                          key: ValueKey(ended),
                          label: ended
                              ? ObCopy.introRaceWin
                              : ObCopy.introRaceHint,
                          won: ended,
                        ),
                      ),
                    ),
                  ),
                  if (ended)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: V13Confetti(
                          particleCount: NuvoMotion.confettiPieces,
                          duration: NuvoMotion.confetti,
                        ),
                      ),
                    ),
                  if (showPointer)
                    const Positioned.fill(
                      child: IgnorePointer(child: _TapPointer()),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Maps bead indices to offsets on the lane's gentle sine path — a
/// miniature of the onboarding Track.
class _LaneGeometry {
  _LaneGeometry({
    required this.width,
    required this.height,
    required this.lastBead,
  });

  final double width;
  final double height;
  final int lastBead;

  static const double _padX = 34;

  Offset beadAt(double bead) {
    final u = (bead / lastBead).clamp(0.0, 1.0);
    final x = _padX + u * (width - 2 * _padX);
    final y = height / 2 + math.sin(u * math.pi * 1.5 - 0.4) * 16;
    return Offset(x, y);
  }
}

/// The lane painting — navy path, bead dots, the finish flag post.
class _Lane extends StatelessWidget {
  const _Lane({required this.lane, required this.ended});

  final _LaneGeometry lane;
  final bool ended;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LanePainter(lane: lane),
      child: Align(
        alignment: Alignment.topRight,
        child: _FinishFlag(dropIn: ended),
      ),
    );
  }
}

class _LanePainter extends CustomPainter {
  const _LanePainter({required this.lane});

  final _LaneGeometry lane;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i <= 40; i++) {
      final p = lane.beadAt(lane.lastBead * i / 40);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = V13.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = V13.outlineThick
        ..strokeCap = StrokeCap.round,
    );
    final ring = Paint()
      ..color = V13.card
      ..style = PaintingStyle.stroke
      ..strokeWidth = V13.outline;
    final fill = Paint()..color = V13.card;
    for (var i = 0; i <= lane.lastBead; i++) {
      canvas.drawCircle(lane.beadAt(i.toDouble()), 3.5, fill);
      canvas.drawCircle(lane.beadAt(i.toDouble()), 3.5, ring);
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) => false;
}

/// A racer token — the user gets the blue ring + "You" label; the ghosts
/// are neutral silhouettes (spec D1: no Nuvo Crew photo assets exist) that
/// bob with [NuvoFloat].
class _Token extends StatelessWidget {
  const _Token({
    required this.lane,
    required this.beads,
    required this.laneOffset,
    required this.isYou,
    required this.float,
  });

  final _LaneGeometry lane;
  final double beads;
  final double laneOffset;
  final bool isYou;
  final bool float;

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    final target = lane.beadAt(beads) + Offset(0, laneOffset);
    final token = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        V13Face(size: 38, isMe: isYou, name: isYou ? ObCopy.you : null),
        if (isYou) ...[
          const SizedBox(height: 2),
          Text(ObCopy.you, style: V13.label.copyWith(color: V13.navy)),
        ],
      ],
    );
    return Positioned(
      left: 0,
      top: 92,
      right: 0,
      bottom: 0,
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(begin: target, end: target),
        duration: reduce ? Duration.zero : NuvoMotion.springDuration,
        curve: NuvoMotion.spring,
        builder: (context, pos, _) {
          final child = float ? NuvoFloat(child: token) : token;
          return Transform.translate(
            offset: pos - const Offset(19, 19),
            child: child,
          );
        },
      ),
    );
  }
}

/// The checkered finish flag at the lane's end — drops in on the win.
class _FinishFlag extends StatelessWidget {
  const _FinishFlag({required this.dropIn});

  final bool dropIn;

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: dropIn ? -46 : 0, end: 0),
      duration: dropIn
          ? (reduce ? Duration.zero : NuvoMotion.springDuration)
          : Duration.zero,
      curve: NuvoMotion.spring,
      builder: (context, dy, child) =>
          Transform.translate(offset: Offset(0, dy), child: child),
      child: const Padding(
        padding: EdgeInsets.only(right: 18, top: 6),
        child: _CheckeredFlag(),
      ),
    );
  }
}

/// A tiny checkered flag — navy pole, alternating squares.
class _CheckeredFlag extends StatelessWidget {
  const _CheckeredFlag();

  @override
  Widget build(BuildContext context) {
    Widget square(Color c) => Container(
      width: 7,
      height: 7,
      color: c,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 3, height: 34, color: V13.navy),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: V13.navy, width: V13.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [square(V13.navy), square(V13.card)],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [square(V13.card), square(V13.navy)],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The hint / win chip at the card's foot.
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.won});

  final String label;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V13.gapLg,
        vertical: V13.gapSm,
      ),
      decoration: BoxDecoration(
        color: won ? V13.mint : V13.card,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: V13.outline),
        boxShadow: V13.hardShadow(x: 2, y: 2),
      ),
      child: Text(
        label,
        style: V13.bodyStrong.copyWith(fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The one-time hand pointer — taps the card once after the idle delay,
/// then fades. Never loops (spec).
class _TapPointer extends StatefulWidget {
  const _TapPointer();

  @override
  State<_TapPointer> createState() => _TapPointerState();
}

class _TapPointerState extends State<_TapPointer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.pointerTap,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl.isAnimating || _ctrl.isCompleted) return;
    if (NuvoMotion.reduceMotionOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        // Press: hand sinks onto the card mid-way, ring pops on contact,
        // the whole cue fades out on the tail.
        final press = (t * 1.6).clamp(0.0, 1.0);
        final dy = -14 + 14 * NuvoMotion.pressDownCurve.transform(press);
        final ring = ((t - 0.45) / 0.3).clamp(0.0, 1.0);
        final fade = t > 0.8 ? 1 - (t - 0.8) / 0.2 : 1.0;
        return Opacity(
          opacity: fade,
          child: Center(
            child: Transform.translate(
              offset: Offset(0, dy + 34),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: ring,
                    child: Opacity(
                      opacity: ring * (1 - ring * 0.5),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: V13.navy,
                            width: V13.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.back_hand_rounded,
                    size: 40,
                    color: V13.navy,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
