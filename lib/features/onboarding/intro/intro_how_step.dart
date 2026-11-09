import 'dart:math' as math;

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

/// S2 — "How it works", one composed screen: a phone frame where a stick
/// figure squats on camera (REPS 1, 2, 3 → "AI Motion verified"), over a
/// leaderboard where YOUR row then climbs 4th → 1st. "Create my player"
/// heads into sign-up; "I already have an account" heads into sign-in —
/// both complete the intros.
///
/// One clock drives everything (see [_HowTimeline]) so the story always
/// reads in order: reps land, the proof verifies, the board answers.
class ObIntroHowStep extends ConsumerStatefulWidget {
  const ObIntroHowStep({super.key});

  @override
  ConsumerState<ObIntroHowStep> createState() => _ObIntroHowStepState();
}

class _ObIntroHowStepState extends ConsumerState<ObIntroHowStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _HowTimeline.total,
  );

  int _reps = 0;
  int _climb = 0;

  void _onTick() {
    final reps = _HowTimeline.repsAt(_elapsed);
    final climb = _HowTimeline.climbAt(_elapsed);
    if (reps == _reps && climb == _climb) return;
    final repUp = reps > _reps;
    final climbUp = climb > _climb;
    _reps = reps;
    _climb = climb;
    if (repUp) {
      NuvoHaptics.light();
      // The verification payoff — a heavier tick and the XP chime the
      // moment the pill is earned.
      if (reps == _HowTimeline.verifyAfter) {
        NuvoHaptics.medium();
        ref.read(nuvoSoundsProvider).xpChime();
      }
    }
    if (climbUp) {
      if (climb == _HowTimeline.rows.length - 1) {
        NuvoHaptics.medium();
        ref.read(nuvoSoundsProvider).xpChime();
      } else {
        NuvoHaptics.light();
        ref.read(nuvoSoundsProvider).pressTick();
      }
    }
  }

  Duration get _elapsed => _clock.duration! * _clock.value;

  /// Tap the phone: replay the demo from rep 0.
  void _restart() {
    NuvoHaptics.select();
    _reps = 0;
    _climb = 0;
    _clock
      ..value = 0
      ..repeat();
  }

  @override
  void initState() {
    super.initState();
    _clock.addListener(_onTick);
    _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _join(AuthIntent intent) {
    ref.read(authIntentProvider.notifier).state = intent;
    obAdvance(context, ref, OnboardingStep.introHow);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.introHow,
      fillHero: true,
      hero: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) =>
            _HowHero(elapsed: _elapsed, onPhoneTap: _restart),
      ),
      title: ObCopy.introHowTitle,
      // Short phones give the room to the demo instead (the title says it).
      subtitle: MediaQuery.sizeOf(context).height < 640
          ? null
          : ObCopy.introHowSub,
      body: Center(
        child: NuvoPressable(
          onTap: () => _join(AuthIntent.signIn),
          semanticLabel: ObCopy.introBoardLogin,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: V13.gapMd,
              vertical: V13.gapSm,
            ),
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

/// The S2 hero (phone demo over the climbing board), exposed so S4 can use
/// the REAL widget as its blurred backdrop instead of a copy that could
/// drift. It shows the end of the story (proof verified, YOU 1st)
/// with every ticker paused and no input.
class ObIntroHowHero extends StatelessWidget {
  const ObIntroHowHero({super.key});

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: false,
      child: IgnorePointer(
        child: _HowHero(elapsed: _HowTimeline.total, onPhoneTap: () {}),
      ),
    );
  }
}

/// The scripted story, in [NuvoMotion] time: three squats (one per
/// [NuvoMotion.squatRep]), then the board climbs one rank per third of a
/// [NuvoMotion.boardTick], then a beat on 1st before the loop restarts.
abstract final class _HowTimeline {
  static const int verifyAfter = 3;
  static final Duration repsEnd = NuvoMotion.squatRep * verifyAfter;
  static final Duration climbStep = NuvoMotion.boardTick ~/ 3;
  static final Duration total =
      repsEnd + NuvoMotion.boardTick + NuvoMotion.squatRep;

  /// Standing rows, best first — YOU start 4th and gain points per climb.
  static const List<_BoardRow> rows = [
    _BoardRow('Maya', 68),
    _BoardRow('Leo', 54),
    _BoardRow('Sam', 41),
    _BoardRow('You', 24, isMe: true),
  ];
  static const List<int> myPoints = [24, 45, 58, 72];

  /// Squat bottoms reached by [t] (the bottom is mid-period).
  static int repsAt(Duration t) {
    final reps = (t.inMicroseconds / NuvoMotion.squatRep.inMicroseconds + 0.5)
        .floor();
    return reps.clamp(0, verifyAfter);
  }

  /// Rank steps climbed by [t] (0 = still 4th, 3 = 1st).
  static int climbAt(Duration t) {
    if (t < repsEnd) return 0;
    final steps =
        1 + ((t - repsEnd).inMicroseconds ~/ climbStep.inMicroseconds);
    return steps.clamp(0, rows.length - 1);
  }

  /// Squat depth 0 → 1 → 0 per rep during the reps phase; standing after.
  static double bendAt(Duration t) {
    if (t >= repsEnd) return 0;
    final f =
        (t.inMicroseconds % NuvoMotion.squatRep.inMicroseconds) /
        NuvoMotion.squatRep.inMicroseconds;
    return math.sin(math.pi * f);
  }
}

class _BoardRow {
  const _BoardRow(this.name, this.points, {this.isMe = false});

  final String name;
  final int points;
  final bool isMe;
}

/// Sizes the phone and the board from the room the shell leaves, then
/// stacks them centered: tall phones get the full ~220x300 frame and
/// 40 px rows, small phones shrink both and keep every pixel in use.
class _HowHero extends StatelessWidget {
  const _HowHero({required this.elapsed, required this.onPhoneTap});

  final Duration elapsed;
  final VoidCallback onPhoneTap;

  static const double _gap = 12;
  static const double _boardPad = 10;
  static const double _rowGap = 5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        // Rows flex between 28 and 40; the phone takes what is left (max
        // 300) but never less than a frame that can hold its two pills.
        final rowH = ((h - _gap - 200 - 2 * _boardPad - 3 * _rowGap) / 4).clamp(
          28.0,
          46.0,
        );
        // + the card's 2 x 2.5 px outline.
        final boardH =
            4 * rowH + 3 * _rowGap + 2 * _boardPad + 2 * V13.outlineThick;
        final phoneH = math.min(330.0, h - _gap - boardH);
        final phoneW = math.min(
          math.min(240.0, c.maxWidth),
          math.max(172.0, phoneH * 220 / 300),
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PhoneDemo(
              key: const ValueKey('ob-camera-card'),
              width: phoneW,
              height: phoneH,
              elapsed: elapsed,
              onTap: onPhoneTap,
            ),
            const SizedBox(height: _gap),
            _BoardDemo(
              key: const ValueKey('ob-board-card'),
              height: boardH,
              rowH: rowH,
              climb: _HowTimeline.climbAt(elapsed),
            ),
          ],
        );
      },
    );
  }
}

// ── Phone ─────────────────────────────────────────────────────────────────

/// The phone frame: notch, viewfinder brackets, the squatting figure, the
/// REPS counter pill and the "AI Motion verified" pill — all inside.
class _PhoneDemo extends StatelessWidget {
  const _PhoneDemo({
    super.key,
    required this.width,
    required this.height,
    required this.elapsed,
    required this.onTap,
  });

  final double width;
  final double height;
  final Duration elapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(V13.radiusCardLg);
    final reps = _HowTimeline.repsAt(elapsed);
    final verified = reps >= _HowTimeline.verifyAfter;
    final compact = height < 200;
    return NuvoPressable(
      onTap: onTap,
      borderRadius: radius,
      shadow: V13.shadow6,
      // The press sinks the frame; the restart select is fired by the step.
      haptic: false,
      semanticLabel: 'Tap to replay the rep counter',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: V13.sky,
          borderRadius: radius,
          border: Border.all(color: V13.navy, width: V13.outlineThick),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SkeletonPainter(
                  bend: _HowTimeline.bendAt(elapsed),
                  headroom: compact ? 26 : 56,
                  footroom: compact ? 46 : 58,
                  // Short frame: the figure steps right of the REPS pill so
                  // both fit without stealing height from each other.
                  centerX: compact ? 0.66 : 0.5,
                ),
              ),
            ),
            // Notch.
            Positioned(
              top: 7,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 36,
                  height: 6,
                  decoration: BoxDecoration(
                    color: V13.navy,
                    borderRadius: BorderRadius.circular(V13.radiusPill),
                  ),
                ),
              ),
            ),
            Positioned(
              top: compact ? 18 : 24,
              left: V13.gapMd,
              child: _RepsPill(reps: reps),
            ),
            Positioned(
              left: V13.gapSm,
              right: V13.gapSm,
              bottom: compact ? V13.gapSm : V13.gapMd,
              child: Center(child: _VerifiedPill(visible: verified)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepsPill extends StatelessWidget {
  const _RepsPill({required this.reps});

  final int reps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V13.gapMd,
        vertical: V13.gapXs,
      ),
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: V13.outline),
        boxShadow: V13.hardShadow(x: 2, y: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('REPS', style: V13.label),
          const SizedBox(width: V13.gapSm),
          V13NumberPop(
            value: reps,
            style: V13.number.copyWith(fontSize: 18, height: 1.15),
          ),
        ],
      ),
    );
  }
}

/// "AI Motion verified" — slides up and fades in after the third rep.
class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 0.6),
      duration: reduce ? Duration.zero : NuvoMotion.springDuration,
      curve: NuvoMotion.spring,
      child: AnimatedOpacity(
        key: const ValueKey('ob-verified-pill'),
        opacity: visible ? 1 : 0,
        duration: reduce ? NuvoMotion.reduceMotionFade : NuvoMotion.enter,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V13.gapMd,
            vertical: V13.gapSm,
          ),
          decoration: BoxDecoration(
            color: V13.mint,
            borderRadius: BorderRadius.circular(V13.radiusPill),
            border: Border.all(color: V13.navy, width: V13.outline),
            boxShadow: V13.hardShadow(x: 2, y: 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: V13.navy,
                ),
                const SizedBox(width: V13.gapXs),
                Text(
                  ObCopy.introCameraPill,
                  maxLines: 1,
                  style: V13.bodyStrong.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the viewfinder (corner brackets, floor line, shadow) and the
/// squatting stick figure: thick rounded navy limbs, round head, blue
/// joints. The pose is forward kinematics over fixed segment lengths, so
/// limbs never stretch; [bend] 0 is standing, 1 is the squat bottom.
///
/// [headroom] / [footroom] are the pixels the pills claim above and below
/// the figure — it is scaled to fit between them, always inside the frame.
class _SkeletonPainter extends CustomPainter {
  const _SkeletonPainter({
    required this.bend,
    required this.headroom,
    required this.footroom,
    required this.centerX,
  });

  final double bend;
  final double headroom;
  final double footroom;

  /// Figure's horizontal center as a fraction of the frame width.
  final double centerX;

  // Segment lengths in figure units (standing height ≈ 134).
  static const double _shin = 30, _thigh = 34, _torso = 36;
  static const double _upper = 20, _fore = 19, _headR = 11;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final navy = V13.navy;

    // ── Viewfinder ─────────────────────────────────────────────────
    final bracket = Paint()
      ..color = navy.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = V13.outline
      ..strokeCap = StrokeCap.round;
    const inset = 14.0;
    const arm = 14.0;
    for (final (cx, cy, sx, sy) in [
      // (top-left omitted — the REPS pill sits there)
      (w - inset, inset + 14, -1.0, 1.0),
      (inset, h - inset, 1.0, -1.0),
      (w - inset, h - inset, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + arm * sx, cy), bracket);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + arm * sy), bracket);
    }

    // ── Figure frame ───────────────────────────────────────────────
    final floorY = h - footroom;
    final availH = floorY - headroom;
    // Standing height: ankle lift 6 + shin + thigh + torso + neck + head.
    const standing = 6 + _shin + _thigh + _torso + 6 + 2 * _headR;
    final k = math.min(availH / standing, w / 135);
    final originX = w * centerX - 12 * k;

    Offset p(double x, double y) => Offset(originX + x * k, floorY + y * k);

    // Floor + soft contact shadow.
    canvas.drawLine(
      Offset(w * 0.18, floorY),
      Offset(w * 0.82, floorY),
      Paint()
        ..color = navy
        ..strokeWidth = V13.outline
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawOval(
      Rect.fromCenter(center: p(10, 0), width: 58 * k, height: 7 * k),
      Paint()..color = navy.withValues(alpha: 0.14),
    );

    // ── Pose (angles from vertical, forward = +) ───────────────────
    double rad(double deg) => deg * math.pi / 180;
    final shinA = rad(_lerp(3, 48, bend));
    final thighA = rad(_lerp(-3, -75, bend)); // knee → hip, leaning back
    final torsoA = rad(_lerp(0, 35, bend));
    final upperA = rad(_lerp(6, 82, bend)); // shoulder → elbow, from down
    final foreA = rad(_lerp(3, 90, bend));

    final ankle = p(0, -6);
    final knee =
        ankle + Offset(math.sin(shinA), -math.cos(shinA)) * (_shin * k);
    final hip =
        knee + Offset(math.sin(thighA), -math.cos(thighA)) * (_thigh * k);
    final shoulder =
        hip + Offset(math.sin(torsoA), -math.cos(torsoA)) * (_torso * k);
    final head =
        shoulder +
        Offset(math.sin(torsoA), -math.cos(torsoA)) * ((6 + _headR) * k);
    final elbow =
        shoulder + Offset(math.sin(upperA), math.cos(upperA)) * (_upper * k);
    final hand = elbow + Offset(math.sin(foreA), math.cos(foreA)) * (_fore * k);
    final toe = ankle + Offset(12 * k, 0);

    final limb = (7.5 * k).clamp(4.5, 9.0);
    Paint bone(double width) => Paint()
      ..color = navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Far-side limbs first — the same pose, offset back and lighter, so the
    // figure reads as a body with two legs and two arms, not a pole.
    final farShift = Offset(-7 * k, 0);
    final far = bone(limb)..color = navy.withValues(alpha: 0.4);
    canvas.drawLine(ankle + farShift, toe + farShift, far);
    canvas.drawLine(ankle + farShift, knee + farShift, far);
    canvas.drawLine(knee + farShift, hip + farShift, far);
    final farArm = bone(limb * 0.85)..color = navy.withValues(alpha: 0.4);
    canvas.drawLine(shoulder + farShift, elbow + farShift, farArm);
    canvas.drawLine(elbow + farShift, hand + farShift, farArm);

    canvas.drawLine(ankle, toe, bone(limb));
    canvas.drawLine(ankle, knee, bone(limb));
    canvas.drawLine(knee, hip, bone(limb));
    canvas.drawLine(hip, shoulder, bone(limb * 1.7)); // chunky torso
    canvas.drawLine(shoulder, elbow, bone(limb * 0.85));
    canvas.drawLine(elbow, hand, bone(limb * 0.85));

    // Head — round, white fill, navy ring.
    canvas.drawCircle(head, _headR * k, Paint()..color = V13.card);
    canvas.drawCircle(
      head,
      _headR * k,
      Paint()
        ..color = navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.5 * k).clamp(2.0, 3.0),
    );

    // Joints — the blue AI tracking dots (white ring so they read on navy).
    final jr = (4.2 * k).clamp(2.8, 5.0);
    for (final j in [shoulder, hip, knee, ankle, elbow, hand]) {
      canvas.drawCircle(j, jr + 1.4, Paint()..color = V13.card);
      canvas.drawCircle(j, jr, Paint()..color = V13.blue);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      old.bend != bend ||
      old.headroom != headroom ||
      old.footroom != footroom ||
      old.centerX != centerX;
}

// ── Board ─────────────────────────────────────────────────────────────────

/// The leaderboard card — four rows filling it, YOUR row springing from 4th
/// to 1st as [climb] steps up, with the gold ring + confetti at 1st.
class _BoardDemo extends StatelessWidget {
  const _BoardDemo({
    super.key,
    required this.height,
    required this.rowH,
    required this.climb,
  });

  final double height;
  final double rowH;
  final int climb;

  static const double _pad = _HowHero._boardPad;
  static const double _gap = _HowHero._rowGap;

  /// Rows with YOUR points for this [climb] step, best first.
  List<(_BoardRow, int)> get _standings {
    final rows = [
      for (final r in _HowTimeline.rows)
        (r, r.isMe ? _HowTimeline.myPoints[climb] : r.points),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    final radius = BorderRadius.circular(V13.radiusCard);
    final standings = _standings;
    final crowned = standings.first.$1.isMe;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: radius,
        border: Border.all(color: V13.navy, width: V13.outlineThick),
        boxShadow: V13.shadow6,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: _pad,
            right: _pad,
            top: _pad,
            bottom: _pad,
            child: Stack(
              children: [
                // Fixed paint order (YOU last, so the climber passes OVER
                // the rows it overtakes); position comes from the rank.
                for (final row in _HowTimeline.rows)
                  AnimatedPositioned(
                    key: ValueKey(row.name),
                    top:
                        standings.indexWhere((e) => e.$1 == row) *
                        (rowH + _gap),
                    left: 0,
                    right: 0,
                    height: rowH,
                    duration: reduce
                        ? Duration.zero
                        : NuvoMotion.springDuration,
                    curve: NuvoMotion.spring,
                    child: _BoardRowTile(
                      row: row,
                      points: standings.firstWhere((e) => e.$1 == row).$2,
                      rank: standings.indexWhere((e) => e.$1 == row) + 1,
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
    );
  }
}

/// One leaderboard row — rank, face, name, points.
class _BoardRowTile extends StatelessWidget {
  const _BoardRowTile({
    required this.row,
    required this.points,
    required this.rank,
    required this.crowned,
  });

  final _BoardRow row;
  final int points;
  final int rank;
  final bool crowned;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final face = (c.maxHeight - 8).clamp(20.0, 30.0);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: V13.gapMd),
          decoration: BoxDecoration(
            color: row.isMe ? V13.sky : V13.bg,
            borderRadius: BorderRadius.circular(V13.radiusTileLg),
            border: Border.all(
              color: row.isMe ? V13.blue : V13.navy,
              width: row.isMe ? V13.outlineThick : V13.outline,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: V13NumberPop(value: rank, style: V13.numberSm),
              ),
              const SizedBox(width: V13.gapSm),
              _CrownRing(
                active: crowned,
                size: face,
                child: V13Face(size: face, isMe: row.isMe),
              ),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: Text(
                  row.name,
                  maxLines: 1,
                  style: V13.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              V13NumberPop(value: points, style: V13.numberSm),
            ],
          ),
        );
      },
    );
  }
}

/// The gold ring flash once YOUR row takes 1st — a one-shot halo around
/// the face (expands, fades, stays as a ring).
class _CrownRing extends StatelessWidget {
  const _CrownRing({
    required this.active,
    required this.size,
    required this.child,
  });

  final bool active;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          child,
          if (active)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: NuvoMotion.springDuration,
              curve: NuvoMotion.spring,
              builder: (context, t, _) => Container(
                width: size + 8 * t,
                height: size + 8 * t,
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
      ),
    );
  }
}
