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

/// S1 — "Race anything." The tap duel is the first thing on screen: a
/// coral hero card (~60% of the screen) holding three stacked lanes — a
/// Nuvo Crew ghost above and below, YOU in the middle. Every tap on the
/// card advances your token one bead along its lane for [NuvoMotion.duelWindow].
///
/// The ghosts are scripted relative to you: they lead early, then concede
/// in the last stretch so a normal tapper always wins by 1–2 beads at the
/// last second (spec: "never lose").
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
  /// Beads per lane — the finish flag sits after bead [_finish]. One tap is
  /// one bead, so a brisk tapper reaches the flag inside the 5 s window.
  static const int _finish = 20;

  /// Ghosts' early lead and final lag, in beads — Maya leads by two and
  /// concedes to one back, Leo leads by one and ends two back.
  static const _leads = [2.0, 1.0];
  static const _lags = [1.0, 2.0];

  /// Race progress (0–1) after which the ghosts concede. Progress is the
  /// larger of elapsed time and the user's distance, so a fast tapper and
  /// a slow one both see the same late swing.
  static const double _concedeFrom = 0.6;

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

  bool get _autoPlaying => _auto.isAnimating || _auto.isCompleted;

  /// The user's bead position (continuous during auto-play, the full lane
  /// once the duel is over).
  double get _userBeads {
    if (_ended) return _finish.toDouble();
    if (_autoPlaying) {
      final u = (_auto.value / 0.8).clamp(0.0, 1.0);
      return _autoBase + (_finish - _autoBase) * u;
    }
    return _count.clamp(0, _finish).toDouble();
  }

  /// Race progress 0–1 — time or distance, whichever is further along.
  double get _progress {
    final time = _autoPlaying ? _auto.value : _duel.value;
    return math.max(time, _userBeads / _finish).clamp(0.0, 1.0);
  }

  /// Ghost [i]'s bead — leads while you tap, then concedes behind you.
  double _ghostBeads(int i) {
    final user = _userBeads;
    if (_ended) return _finish - _lags[i];
    final c = ((_progress - _concedeFrom) / (1 - _concedeFrom)).clamp(0.0, 1.0);
    final lead = _leads[i] * (user / 3).clamp(0.0, 1.0);
    final g = user + lead + (-_lags[i] - lead) * c * c;
    return g.clamp(0.0, _finish - 1.0);
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
      if (status == AnimationStatus.completed) _finishDuel();
    });
    _duel.addListener(_onRaceClock);
    _auto.addListener(_onRaceClock);
    _auto.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      // The win plays out; the player continues with an explicit tap.
      _finishDuel();
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
  /// bead per tap with the spec's tick + selectionClick. Reaching the flag
  /// ends the duel on the spot.
  void _onCardTap() {
    if (_ended || _autoPlaying) return;
    if (!_started) {
      _started = true;
      _idleTimer?.cancel();
      _duel.forward();
    }
    setState(() {
      _count++;
      _showPointer = false;
    });
    NuvoHaptics.select();
    ref.read(nuvoSoundsProvider).pressTick();
    if (_count >= _finish) {
      _duel.stop();
      _finishDuel();
    }
  }

  /// The duel resolves: everyone settles on the flag, confetti,
  /// mediumImpact, the win chip.
  void _finishDuel() {
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

  /// Next — pressable any time. An early press fast-forwards the duel to its
  /// scripted win inside [NuvoMotion.duelAutoPlay]; it never advances on
  /// its own, a second tap continues.
  void _onNext() {
    if (_advanced) return;
    if (_ended) {
      _advance();
      return;
    }
    if (_auto.isAnimating) return;
    _idleTimer?.cancel();
    setState(() {
      _autoBase = _count.clamp(0, _finish);
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
      fillHero: true,
      hero: _DuelCard(
        count: _count,
        lanes: [
          _LaneState(
            name: ObCopy.introRaceGhostA,
            beads: _ghostBeads(0),
            kind: _LaneKind.ghost,
          ),
          _LaneState(name: ObCopy.you, beads: _userBeads, kind: _LaneKind.you),
          _LaneState(
            name: ObCopy.introRaceGhostB,
            beads: _ghostBeads(1),
            kind: _LaneKind.ghost,
          ),
        ],
        finish: _finish,
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

enum _LaneKind { ghost, you }

class _LaneState {
  const _LaneState({
    required this.name,
    required this.beads,
    required this.kind,
  });

  final String name;
  final double beads;
  final _LaneKind kind;
}

/// The coral race card — header (tap count + hint/win chip) over three
/// stacked lanes. The whole card is the tap surface.
class _DuelCard extends StatelessWidget {
  const _DuelCard({
    required this.count,
    required this.lanes,
    required this.finish,
    required this.ended,
    required this.showPointer,
    required this.onTap,
  });

  final int count;
  final List<_LaneState> lanes;
  final int finish;
  final bool ended;
  final bool showPointer;
  final VoidCallback onTap;

  static const double _pad = 16;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(V13.radiusCardLg);
    return NuvoPressable(
      onTap: onTap,
      borderRadius: radius,
      shadow: V13.shadow6,
      // The press sinks the card; the per-bead tick is fired by the step
      // (selectionClick + pressTick), not the pressable's light.
      haptic: false,
      semanticLabel: ObCopy.introRaceHint,
      child: Container(
        key: const ValueKey('ob-duel-card'),
        decoration: BoxDecoration(
          color: V13.coral,
          borderRadius: radius,
          border: Border.all(color: V13.navy, width: V13.outlineThick),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(_pad),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      V13NumberPop(
                        value: count,
                        style: V13.hugeNumber.copyWith(fontSize: 38),
                      ),
                      const SizedBox(width: V13.gapSm),
                      Text(ObCopy.introRaceTaps, style: V13.label),
                      const SizedBox(width: V13.gapMd),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
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
                    ],
                  ),
                ),
                const SizedBox(height: _gap),
                for (var i = 0; i < lanes.length; i++) ...[
                  if (i > 0) const SizedBox(height: _gap),
                  Expanded(
                    child: _Lane(state: lanes[i], finish: finish, ended: ended),
                  ),
                ],
              ],
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
              const Positioned.fill(child: IgnorePointer(child: _TapPointer())),
          ],
        ),
      ),
    );
  }
}

/// One horizontal lane — name pill over a bead row, the racer token riding
/// the beads, and the finish flag at the end. The token is clamped to the
/// bead row, so it can never leave the lane or reach the flag's pole.
class _Lane extends StatelessWidget {
  const _Lane({required this.state, required this.finish, required this.ended});

  final _LaneState state;
  final int finish;
  final bool ended;

  static const double _inset = 12;
  static const double _pillH = 20;
  static const double _flagW = 24;

  @override
  Widget build(BuildContext context) {
    final you = state.kind == _LaneKind.you;
    final reduce = NuvoMotion.reduceMotionOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        // Tokens, beads and flag grow with the lane so tall phones are
        // not a sea of white.
        final token = math
            .min(h * 0.4, h - _inset - _pillH - 12)
            .clamp(26.0, 68.0);
        final grow = (token / 34).clamp(1.0, 1.9);
        final r = token / 2;
        // The bead row sits centered in the space under the pill.
        final rowTop = _inset + _pillH;
        final beadY = rowTop + (h - rowTop - 6) / 2;
        final startX = _inset + r;
        final endX = w - _inset - _flagW - 12 - r;
        double xFor(double beads) =>
            startX + (endX - startX) * (beads / finish).clamp(0.0, 1.0);
        return Container(
          decoration: BoxDecoration(
            color: V13.card,
            borderRadius: BorderRadius.circular(V13.radiusCard - 6),
            border: Border.all(
              color: you ? V13.blue : V13.navy,
              width: you ? V13.outlineThick : V13.outline,
            ),
            boxShadow: V13.hardShadow(x: 0, y: 3),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BeadsPainter(
                    startX: startX,
                    endX: endX,
                    y: beadY,
                    count: finish,
                    reached: state.beads,
                    beadR: 2.5 * grow.clamp(1.0, 1.4),
                  ),
                ),
              ),
              Positioned(
                left: _inset,
                top: _inset - 4,
                child: Transform.scale(
                  scale: grow.clamp(1.0, 1.25),
                  alignment: Alignment.topLeft,
                  child: _NamePill(name: state.name, you: you),
                ),
              ),
              Positioned(
                right: _inset,
                top: beadY - 17,
                child: Transform.scale(
                  scale: grow.clamp(1.0, 1.5),
                  alignment: Alignment.centerRight,
                  child: const _CheckeredFlag(),
                ),
              ),
              AnimatedPositioned(
                duration: reduce ? Duration.zero : NuvoMotion.pressDown,
                curve: NuvoMotion.pressDownCurve,
                left: xFor(state.beads) - r,
                top: beadY - r,
                width: token,
                height: token,
                child: V13Face(size: token, isMe: you),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The dotted bead row — beads you have passed fill in navy.
class _BeadsPainter extends CustomPainter {
  const _BeadsPainter({
    required this.startX,
    required this.endX,
    required this.y,
    required this.count,
    required this.reached,
    required this.beadR,
  });

  final double startX;
  final double endX;
  final double y;
  final int count;
  final double reached;
  final double beadR;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = V13.navy.withValues(alpha: 0.22);
    final lit = Paint()..color = V13.navy;
    for (var i = 0; i <= count; i++) {
      final x = startX + (endX - startX) * i / count;
      canvas.drawCircle(Offset(x, y), beadR, i <= reached ? lit : dim);
    }
  }

  @override
  bool shouldRepaint(_BeadsPainter old) =>
      old.reached != reached ||
      old.beadR != beadR ||
      old.startX != startX ||
      old.endX != endX ||
      old.y != y;
}

/// "You" (blue — the one place blue marks the player) or a ghost's name.
class _NamePill extends StatelessWidget {
  const _NamePill({required this.name, required this.you});

  final String name;
  final bool you;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: V13.gapMd),
      decoration: BoxDecoration(
        color: you ? V13.blue : V13.bg,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: Text(
        name,
        maxLines: 1,
        style: V13.label.copyWith(
          fontSize: 10.5,
          height: 1.1,
          color: you ? V13.white : V13.navy,
        ),
      ),
    );
  }
}

/// A tiny checkered finish flag — navy pole, 2x2 squares. 24 x 34.
class _CheckeredFlag extends StatelessWidget {
  const _CheckeredFlag();

  @override
  Widget build(BuildContext context) {
    Widget square(Color c) => Container(width: 8, height: 8, color: c);
    return SizedBox(
      width: 24,
      height: 34,
      child: Row(
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
      ),
    );
  }
}

/// The hint / win chip in the header.
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.won});

  final String label;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V13.gapMd,
        vertical: V13.gapSm,
      ),
      decoration: BoxDecoration(
        color: won ? V13.mint : V13.card,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: V13.outline),
        boxShadow: V13.hardShadow(x: 2, y: 2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: V13.bodyStrong.copyWith(fontSize: 13),
        ),
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
