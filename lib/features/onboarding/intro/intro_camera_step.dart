import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../../core/v13/widgets/v13_number_pop.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';

/// S2 — "Prove it on camera." A phone-outline camera view where a
/// stick-figure skeleton (navy bones, blue joints) loops squats on its
/// own. The rep counter pops on each squat bottom with a lightImpact;
/// once the third rep lands, the "AI Motion verified" pill slides in.
/// Tapping the card restarts the count (spec: "runs by itself; tap
/// restarts").
class ObIntroCameraStep extends ConsumerStatefulWidget {
  const ObIntroCameraStep({super.key});

  @override
  ConsumerState<ObIntroCameraStep> createState() =>
      _ObIntroCameraStepState();
}

class _ObIntroCameraStepState extends ConsumerState<ObIntroCameraStep>
    with SingleTickerProviderStateMixin {
  /// The loop hits the squat bottom at t = .5 of each period.
  static const double _bottomAt = 0.5;

  /// Reps that must land before the verified pill slides in (spec).
  static const int _verifyAfter = 3;

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: NuvoMotion.squatRep,
  );

  int _reps = 0;
  bool _pastBottom = false;

  /// Squat depth 0 → 1 → 0 over one period (smooth, no curve needed).
  double get _bend => math.sin(math.pi * _loop.value);

  void _onTick() {
    final past = _loop.value >= _bottomAt;
    if (past == _pastBottom) return;
    _pastBottom = past;
    if (!past) return;
    setState(() => _reps++);
    NuvoHaptics.light();
  }

  void _restart() {
    setState(() {
      _reps = 0;
      _pastBottom = _loop.value >= _bottomAt;
    });
    _loop.forward(from: 0);
    NuvoHaptics.select();
  }

  @override
  void initState() {
    super.initState();
    _loop.addListener(_onTick);
    _loop.repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return OnboardingShell(
      step: OnboardingStep.introCamera,
      hero: _CameraCard(
        bend: _bend,
        loop: _loop,
        reps: _reps,
        verified: _reps >= _verifyAfter,
        onTap: _restart,
      ),
      title: ObCopy.introCameraTitle,
      subtitle: ObCopy.introCameraSub,
      ctaLabel: ObCopy.next,
      onCta: () => obAdvance(context, ref, OnboardingStep.introCamera),
      onBack: flow.goBack,
      onSkip: flow.skipIntros,
    );
  }
}

/// The phone-outline camera card — viewfinder brackets, the animated
/// skeleton painter, the rep counter and the verified pill.
class _CameraCard extends StatelessWidget {
  const _CameraCard({
    required this.bend,
    required this.loop,
    required this.reps,
    required this.verified,
    required this.onTap,
  });

  final double bend;
  final Animation<double> loop;
  final int reps;
  final bool verified;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(V13.radiusCardLg);
    return Center(
      child: NuvoPressable(
        onTap: onTap,
        borderRadius: radius,
        shadow: V13.shadow6,
        // The press sinks the card; the restart select is fired by the
        // step, not the pressable's light.
        haptic: false,
        semanticLabel: 'Tap to restart the rep counter',
        child: Container(
          key: const ValueKey('ob-camera-card'),
          height: 300,
          decoration: BoxDecoration(
            color: V13.card,
            borderRadius: radius,
            border: Border.all(color: V13.navy, width: V13.outlineThick),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: loop,
                  builder: (context, _) => CustomPaint(
                    painter: _SkeletonPainter(bend: bend),
                  ),
                ),
              ),
              Positioned(
                top: V13.gapMd,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V13.gapMd,
                      vertical: V13.gapXs,
                    ),
                    decoration: BoxDecoration(
                      color: V13.card,
                      borderRadius: BorderRadius.circular(V13.radiusPill),
                      border: Border.all(
                        color: V13.navy,
                        width: V13.outline,
                      ),
                      boxShadow: V13.hardShadow(x: 2, y: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('REPS', style: V13.label),
                        const SizedBox(width: V13.gapXs),
                        V13NumberPop(
                          value: reps,
                          style: V13.number.copyWith(fontSize: 20),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: V13.gapLg,
                child: Center(
                  child: _VerifiedPill(visible: verified),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "AI Motion verified" — slides up in after the third rep lands.
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
        duration: reduce
            ? NuvoMotion.reduceMotionFade
            : NuvoMotion.enter,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V13.gapMd,
            vertical: V13.gapSm,
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
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: V13.blue,
              ),
              const SizedBox(width: V13.gapXs),
              Text(
                ObCopy.introCameraPill,
                style: V13.bodyStrong.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the viewfinder (corner brackets + floor line) and the squatting
/// skeleton — navy bones, blue joints, head on a navy-stroked circle.
/// [bend] 0 is standing, 1 is the squat bottom; joints lerp between the
/// two poses so the loop needs no rig.
class _SkeletonPainter extends CustomPainter {
  const _SkeletonPainter({required this.bend});

  final double bend;

  static Offset _lerp(Offset a, Offset b, double t) => Offset(
        a.dx + (b.dx - a.dx) * t,
        a.dy + (b.dy - a.dy) * t,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final gy = size.height - 34; // floor line
    final cx = w / 2;

    // ── Viewfinder ─────────────────────────────────────────────────
    final bracket = Paint()
      ..color = V13.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = V13.outline
      ..strokeCap = StrokeCap.round;
    const corner = 16.0;
    const arm = 12.0;
    for (final (dx, dy) in [
      (corner, corner),
      (w - corner, corner),
      (corner, size.height - corner),
      (w - corner, size.height - corner),
    ]) {
      final sx = dx < w / 2 ? 1.0 : -1.0;
      final sy = dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawLine(
        Offset(dx, dy),
        Offset(dx + arm * sx, dy),
        bracket,
      );
      canvas.drawLine(
        Offset(dx, dy),
        Offset(dx, dy + arm * sy),
        bracket,
      );
    }
    // Floor.
    canvas.drawLine(
      Offset(cx - 70, gy),
      Offset(cx + 70, gy),
      Paint()
        ..color = V13.navy
        ..strokeWidth = V13.outline
        ..strokeCap = StrokeCap.round,
    );

    // ── Pose — standing → squat-bottom keyframes, side view. ──────
    final hip = _lerp(
      Offset(cx, gy - 58),
      Offset(cx - 8, gy - 28),
      bend,
    );
    final knee = _lerp(
      Offset(cx + 16, gy - 30),
      Offset(cx + 30, gy - 34),
      bend,
    );
    final ankle = Offset(cx + 10, gy - 2);
    final toe = ankle + const Offset(12, 0);
    final shoulder = _lerp(
      Offset(cx - 2, gy - 104),
      Offset(cx + 12, gy - 78),
      bend,
    );
    final head = shoulder + const Offset(4, -16);
    // Arms hang at rest, reach forward at depth.
    final elbow = _lerp(
      shoulder + const Offset(6, 24),
      shoulder + const Offset(18, 16),
      bend,
    );
    final hand = _lerp(
      shoulder + const Offset(12, 46),
      shoulder + const Offset(34, 26),
      bend,
    );

    final bone = Paint()
      ..color = V13.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = V13.outlineThick
      ..strokeCap = StrokeCap.round;
    void seg(Offset a, Offset b) => canvas.drawLine(a, b, bone);

    seg(hip, shoulder); // torso
    seg(hip, knee); // thigh
    seg(knee, ankle); // shin
    seg(ankle, toe); // foot
    seg(shoulder, elbow); // upper arm
    seg(elbow, hand); // forearm

    // Head — stroked circle, keeps the figure human not abstract.
    canvas.drawCircle(
      head,
      11,
      Paint()..color = V13.card,
    );
    canvas.drawCircle(
      head,
      11,
      Paint()
        ..color = V13.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = V13.outlineThick,
    );

    // Joints — the blue "AI" tracking dots.
    final joint = Paint()..color = V13.blue;
    for (final p in [shoulder, hip, knee, ankle, elbow, hand]) {
      canvas.drawCircle(p, 4, joint);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => old.bend != bend;
}
