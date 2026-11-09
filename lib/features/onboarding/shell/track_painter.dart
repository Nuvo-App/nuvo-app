import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import 'onboarding_shell_controller.dart';

/// The persistent Track — the navy 2.5 px curved path with one bead per
/// step that runs behind every onboarding screen.
///
/// Spec (`docs/redesign/onboarding-v2-spec.md` §THE TRACK): beads per step,
/// the path pans 420 ms ease-in-out cubic on each advance at parallax 1.0x
/// while the bead layer runs at 1.15x (arriving early, converging at rest),
/// and the avatar bead springs to its next bead. Never resets — the pan's
/// origin comes from [OnboardingShellController.trackFrom] so an incoming
/// step's track continues the same flight.
///
/// Reduce-motion: the pan never animates; the track snaps to the new step.
class TrackBackground extends StatefulWidget {
  const TrackBackground({super.key, required this.controller});

  final OnboardingShellController controller;

  @override
  State<TrackBackground> createState() => _TrackBackgroundState();
}

class _TrackBackgroundState extends State<TrackBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.trackPan,
  );

  double _from = 0;
  double _to = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _from = widget.controller.trackFrom.toDouble();
    _to = widget.controller.trackIndex.toDouble();
    if (NuvoMotion.reduceMotionOf(context) || _from == _to) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final pan = NuvoMotion.trackPanCurve.transform(t);
            final beadT = (pan * NuvoMotion.trackParallax).clamp(0.0, 1.0);
            return CustomPaint(
              painter: TrackPainter(
                pathProgress: _from + (_to - _from) * pan,
                beadProgress: _from + (_to - _from) * beadT,
                avatarProgress:
                    _from + (_to - _from) * NuvoMotion.spring.transform(t),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints the winding path + step beads. Pure function of three progress
/// values (path, bead layer, avatar) so the parallax is a painter input,
/// not a painter decision — tests can drive it directly.
class TrackPainter extends CustomPainter {
  const TrackPainter({
    required this.pathProgress,
    required this.beadProgress,
    required this.avatarProgress,
    this.totalSteps = 17,
    this.spacing = 88,
  });

  /// Camera position along the path, in steps.
  final double pathProgress;

  /// The bead layer's position — [NuvoMotion.trackParallax] times the
  /// path's own progress while panning (the 1.15x foreground read).
  final double beadProgress;

  /// The avatar bead's position — driven by [NuvoMotion.spring] so it
  /// springs to the next bead rather than easing.
  final double avatarProgress;

  /// Beads drawn — one per [OnboardingStep].
  final int totalSteps;

  /// Vertical distance between beads.
  final double spacing;

  /// The path wanders ±this fraction of the width around the center.
  static const double _wander = 0.17;

  /// Radians of sine per bead of track — the path's curve frequency.
  static const double _curve = 0.85;

  double _xFor(double worldY, double width) =>
      width / 2 + math.sin(worldY / spacing * _curve) * width * _wander;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * 0.44;
    double screenY(double worldY, double progress) =>
        centerY + worldY - progress * spacing;

    // ── The path: one continuous sine through bead space ──────────────
    final path = Path();
    const step = 24.0;
    final top = -spacing * 2;
    final bottom = size.height + spacing * 2;
    var first = true;
    for (var y = top; y <= bottom; y += step) {
      final worldY = y - centerY + pathProgress * spacing;
      final x = _xFor(worldY, size.width);
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = V13.navy.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = V13.outlineThick
        ..strokeCap = StrokeCap.round,
    );

    // ── Beads: filled behind the avatar, outlined ahead of it ─────────
    final fill = Paint()..color = V13.navy;
    final ring = Paint()
      ..color = V13.navy.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = V13.outline;
    for (var i = 0; i < totalSteps; i++) {
      final y = screenY(i * spacing, beadProgress);
      if (y < -spacing || y > size.height + spacing) continue;
      final center = Offset(_xFor(i * spacing, size.width), y);
      if (i < avatarProgress.round()) {
        canvas.drawCircle(center, 4.5, fill);
      } else if (i != avatarProgress.round()) {
        canvas.drawCircle(center, 4.5, ring);
      }
    }

    // ── The avatar bead: the racer token on the track ──────────────────
    final avatarWorldY = avatarProgress * spacing;
    final avatarCenter = Offset(
      _xFor(avatarWorldY, size.width),
      screenY(avatarWorldY, beadProgress),
    );
    canvas.drawCircle(avatarCenter, 11, Paint()..color = V13.blue);
    canvas.drawCircle(
      avatarCenter,
      11,
      Paint()
        ..color = V13.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = V13.outline,
    );
    canvas.drawCircle(avatarCenter, 4.5, Paint()..color = V13.white);
  }

  @override
  bool shouldRepaint(TrackPainter old) =>
      pathProgress != old.pathProgress ||
      beadProgress != old.beadProgress ||
      avatarProgress != old.avatarProgress ||
      totalSteps != old.totalSteps;
}
