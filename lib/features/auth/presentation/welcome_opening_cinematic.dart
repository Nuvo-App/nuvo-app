import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/nuvo_responsive.dart';

/// One opening per mounted onboarding presentation. No account state is written.
class WelcomeOpeningCinematic extends StatefulWidget {
  const WelcomeOpeningCinematic({super.key, required this.onComplete});

  final VoidCallback onComplete;

  // Storyboard (ms): 0–400 blank hold, 400–3400 path drawing, 3400–3900
  // finish arrival (posts + overlapping blue element), 3900–4800 final hold.
  // See _OpeningPathPainter for the exact per-phase breakdown.
  static const duration = Duration(milliseconds: 4800);
  static const reducedMotionHold = Duration(milliseconds: 400);

  @override
  State<WelcomeOpeningCinematic> createState() =>
      _WelcomeOpeningCinematicState();
}

class _WelcomeOpeningCinematicState extends State<WelcomeOpeningCinematic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;
  bool _completed = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: WelcomeOpeningCinematic.duration,
      // The static reduced-motion composition still gets its full reading hold.
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      _reducedMotion = reducedMotion;
      if (_reducedMotion) {
        _controller.duration = WelcomeOpeningCinematic.reducedMotionHold;
      }
      _controller.forward();
    } else if (reducedMotion && !_reducedMotion && !_completed) {
      // An accessibility change can finish the drawing, never restart it.
      _reducedMotion = true;
      _controller.animateTo(
        1,
        duration: WelcomeOpeningCinematic.reducedMotionHold,
      );
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _completed) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          WelcomeOpeningPath(progress: _reducedMotion ? 1 : _controller.value),
    ),
  );
}

/// Pure, constraint-sized drawing, separate from playback and completion.
/// A future onboarding composition can retain/transform this at progress 1.
/// The owning screen supplies the page background and SafeArea.
class WelcomeOpeningPath extends StatelessWidget {
  const WelcomeOpeningPath({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: context.rs(22),
      vertical: context.rs(20),
    ),
    child: CustomPaint(
      painter: _OpeningPathPainter(
        progress: progress.clamp(0.0, 1.0),
        scale: context.nuvoScale,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _OpeningPathPainter extends CustomPainter {
  const _OpeningPathPainter({required this.progress, required this.scale});

  final double progress;
  final double scale;

  // Drawing window: 400ms blank hold, then 3000ms of travel (400–3400ms).
  static const _drawingStart = 400.0;
  static const _drawingSpan = 3000.0;

  // A single smooth curve, not several joined segments: easeInOutCubic is
  // slow at both ends and quickest through the middle — controlled launch,
  // confident travel, controlled arrival — without the velocity
  // discontinuities a hand-stitched multi-segment curve produces at its
  // joins (segments can match in value at a join while still disagreeing
  // in slope, which reads as a visible "hiccup").
  static double _travelProgress(double t) =>
      Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final milliseconds =
        progress * WelcomeOpeningCinematic.duration.inMilliseconds;
    final travel = _travelProgress(
      (milliseconds - _drawingStart) / _drawingSpan,
    );
    if (travel <= 0) return;

    // The route's geometry is fixed — only how much of it is revealed
    // changes with `travel`. Previously the control points themselves were
    // lerped from a shared center toward these positions using the same
    // `travel` value that also drove how much of the (then-reshaping) path
    // was extracted each frame. That coupling made the curve a different
    // shape and length every frame, which is what actually produced the
    // choppy/broken look — not a framerate or easing problem on its own.
    final start = Offset(size.width * .05, size.height * .82);
    final firstControl = Offset(size.width * .24, size.height * .05);
    final secondControl = Offset(size.width * .55, size.height * .98);
    final destination = Offset(size.width * .78, size.height * .14);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        firstControl.dx,
        firstControl.dy,
        secondControl.dx,
        secondControl.dy,
        destination.dx,
        destination.dy,
      );
    final metric = route.computeMetrics().first;
    // Both strokes are drawn from this exact same revealed path, so they
    // are never at risk of revealing at different effective rates.
    final revealed = metric.extractPath(0, metric.length * travel);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      revealed,
      stroke
        ..color = NuvoColors.navy
        ..strokeWidth = 19 * scale,
    );
    canvas.drawPath(
      revealed,
      stroke
        ..color = NuvoColors.blue
        ..strokeWidth = 8 * scale,
    );

    // Posts complete 3400–3650ms; the blue element completes 3550–3850ms,
    // overlapping the posts rather than waiting for them to finish first.
    final postsProgress = ((milliseconds - 3400) / 250).clamp(0.0, 1.0);
    final crossbarProgress = ((milliseconds - 3550) / 300).clamp(0.0, 1.0);
    if (postsProgress > 0) {
      _drawFinish(canvas, destination, postsProgress, crossbarProgress);
    }
  }

  void _drawFinish(
    Canvas canvas,
    Offset destination,
    double postsProgress,
    double crossbarProgress,
  ) {
    // The settle scale follows whichever element is still forming, so it
    // reads as one composition completing rather than snapping early.
    final settle = Curves.easeOutCubic.transform(
      math.max(postsProgress, crossbarProgress),
    );
    final posts = Curves.easeOutCubic.transform(postsProgress);
    final crossbar = Curves.easeOutCubic.transform(crossbarProgress);
    canvas.save();
    canvas.translate(destination.dx, destination.dy);
    canvas.scale(scale * lerpDouble(.96, 1, settle)!);

    // Compact finish gate: two structural posts, one blue lintel, a quiet tick.
    // The route ends inside the gate, rather than beside a detached flagpole.
    final ink = Paint()
      ..color = NuvoColors.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final x in [-17.0, 17.0]) {
      canvas.drawLine(Offset(x, 5), Offset(x, lerpDouble(5, -24, posts)!), ink);
    }
    if (crossbar > 0) {
      final bar = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-20, -33, 40, 16),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        bar,
        Paint()..color = NuvoColors.blue.withValues(alpha: crossbar),
      );
      canvas.drawRRect(
        bar,
        ink
          ..color = NuvoColors.navy.withValues(alpha: crossbar)
          ..strokeWidth = 3,
      );
      canvas.drawPath(
        Path()
          ..moveTo(-4, -25)
          ..lineTo(-1, -22)
          ..lineTo(5, -28),
        ink
          ..color = NuvoColors.page.withValues(alpha: crossbar)
          ..strokeWidth = 2.5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OpeningPathPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.scale != scale;
}
