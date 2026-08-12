import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';
import 'pressable_scale.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// VERIFIED MOTION THREAD
//
// Nuvo's signature visual element — a precise electric-blue trajectory that
// travels through the interface and changes meaning on each page.
//
// Movement becomes proof. Proof becomes progress. Progress becomes
// competition. Competition becomes community.
// ═══════════════════════════════════════════════════════════════════════════════

/// The visual character of a Verified Motion Thread path.
enum MotionPathStyle {
  /// Arena — a gentle rising editorial curve from start to finish.
  editorial,

  /// Compete — parallel lanes for head-to-head trajectories.
  parallel,

  /// Verify — a transformation from scattered traces to a crisp verified path.
  transformation,

  /// Crew — radial connections from a central node.
  network,

  /// Profile — a horizontal timeline with milestone markers.
  timeline,
}

/// A marker anchored to a specific position on the Motion Thread.
class MotionMarker {
  const MotionMarker({
    required this.progress,
    required this.label,
    this.isCurrentUser = false,
    this.isLeader = false,
    this.photoUrl,
    this.initials,
    this.size = 28,
  });

  /// Position along the path, 0.0 to 1.0.
  final double progress;

  final String label;
  final bool isCurrentUser;
  final bool isLeader;
  final String? photoUrl;
  final String? initials;
  final double size;
}

/// The core Verified Motion Thread painter.
///
/// Draws a precise electric-blue trajectory with:
/// - A pale-blue full track
/// - Electric-blue drawn progress
/// - Fine measurement ticks
/// - A finish beacon at the destination
/// - Avatar/status markers at their actual positions
class VerifiedMotionPainter extends CustomPainter {
  const VerifiedMotionPainter({
    required this.progress,
    required this.style,
    this.markers = const [],
    this.secondaryProgress,
    this.showTicks = true,
    this.showFinish = true,
    this.transformPhase = 0,
  });

  /// Primary progress 0.0–1.0.
  final double progress;

  /// Visual composition style.
  final MotionPathStyle style;

  /// Markers to place on the path.
  final List<MotionMarker> markers;

  /// Optional secondary progress (opponent lane in parallel mode).
  final double? secondaryProgress;

  /// Show measurement ticks along the path.
  final bool showTicks;

  /// Show the finish beacon at the end.
  final bool showFinish;

  /// 0–1 phase for the transformation style (0 = scattered, 1 = organized).
  final double transformPhase;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case MotionPathStyle.editorial:
        _paintEditorial(canvas, size);
      case MotionPathStyle.parallel:
        _paintParallel(canvas, size);
      case MotionPathStyle.transformation:
        _paintTransformation(canvas, size);
      case MotionPathStyle.network:
        _paintNetwork(canvas, size);
      case MotionPathStyle.timeline:
        _paintTimeline(canvas, size);
    }
  }

  // ── Editorial: Arena's Next Move Path ──────────────────────────────────────

  void _paintEditorial(Canvas canvas, Size size) {
    final path = _editorialPath(size);
    final t = progress.clamp(0.0, 1.0);

    // Full pale-blue track.
    _drawTrack(canvas, path, NuvoColors.secondarySurface, 7);

    // Measurement ticks.
    if (showTicks) _drawTicks(canvas, path, size);

    // Finish beacon.
    if (showFinish) _drawFinishBeacon(canvas, path, size);

    // Drawn blue progress.
    if (t > 0) _drawProgress(canvas, path, t, NuvoColors.blue, 7);

    // Markers.
    _drawMarkers(canvas, path, size);
  }

  Path _editorialPath(Size size) {
    final startX = 8.0;
    final endX = size.width - 22;
    final baseY = size.height - 18;
    final riseY = 14.0;
    return Path()
      ..moveTo(startX, baseY)
      ..cubicTo(
        startX + (endX - startX) * 0.35, baseY + 1,
        startX + (endX - startX) * 0.62, riseY + 4,
        endX, riseY,
      );
  }

  // ── Parallel: Compete's head-to-head lanes ─────────────────────────────────

  void _paintParallel(Canvas canvas, Size size) {
    final userY = size.height * 0.32;
    final oppY = size.height * 0.68;
    final startX = 8.0;
    final endX = size.width - 22;

    // Two parallel tracks.
    final userPath = Path()
      ..moveTo(startX, userY)
      ..cubicTo(startX + (endX - startX) * 0.4, userY, startX + (endX - startX) * 0.6, userY, endX, userY);
    final oppPath = Path()
      ..moveTo(startX, oppY)
      ..cubicTo(startX + (endX - startX) * 0.4, oppY, startX + (endX - startX) * 0.6, oppY, endX, oppY);

    // Tracks.
    _drawTrack(canvas, userPath, NuvoColors.secondarySurface, 5);
    _drawTrack(canvas, oppPath, NuvoColors.secondarySurface, 5);

    // Ticks on both lanes.
    if (showTicks) {
      _drawTicksOnPath(canvas, userPath, size);
      _drawTicksOnPath(canvas, oppPath, size);
    }

    // Finish beacon (shared).
    if (showFinish) {
      final finishY = (userY + oppY) / 2;
      canvas.drawLine(
        Offset(endX, userY - 4),
        Offset(endX, oppY + 4),
        Paint()
          ..color = NuvoColors.border
          ..strokeWidth = 1.5,
      );
      // Checkered finish marker.
      _drawCheckeredFinish(canvas, Offset(endX + 2, userY), Offset(endX + 2, oppY));
    }

    // Progress.
    final t = progress.clamp(0.0, 1.0);
    if (t > 0) _drawProgress(canvas, userPath, t, NuvoColors.blue, 5);

    final st = (secondaryProgress ?? 0).clamp(0.0, 1.0);
    if (st > 0) _drawProgress(canvas, oppPath, st, NuvoColors.textMuted.withValues(alpha: 0.5), 5);

    // Markers on user lane.
    for (final m in markers) {
      final p = _pointAt(userPath, m.progress.clamp(0.0, 1.0));
      _drawAvatarMarker(canvas, p, m);
    }
  }

  // ── Transformation: Verify's proof flow ────────────────────────────────────

  void _paintTransformation(Canvas canvas, Size size) {
    final phase = transformPhase.clamp(0.0, 1.0);
    final cx = size.width / 2;
    final cy = size.height / 2;

    if (phase < 0.33) {
      // Phase 1: Raw scattered movement traces.
      _drawRawTraces(canvas, size, phase / 0.33);
    } else if (phase < 0.66) {
      // Phase 2: Traces organizing into a path.
      _drawRawTraces(canvas, size, 1.0 - (phase - 0.33) / 0.33);
      final path = _transformationPath(size);
      _drawProgress(canvas, path, (phase - 0.33) / 0.33, NuvoColors.blue.withValues(alpha: 0.5), 5);
    } else {
      // Phase 3: Crisp verified path.
      final path = _transformationPath(size);
      _drawTrack(canvas, path, NuvoColors.secondarySurface, 5);
      _drawProgress(canvas, path, 1.0, NuvoColors.blue, 5);
      // Verified seal.
      _drawVerifiedSeal(canvas, Offset(cx, cy), (phase - 0.66) / 0.34);
    }
  }

  Path _transformationPath(Size size) {
    return Path()
      ..moveTo(12, size.height - 12)
      ..cubicTo(
        size.width * 0.3, size.height * 0.8,
        size.width * 0.5, size.height * 0.5,
        size.width * 0.7, size.height * 0.3,
      )
      ..cubicTo(
        size.width * 0.85, size.height * 0.15,
        size.width - 16, size.height * 0.12,
        size.width - 12, 12,
      );
  }

  void _drawRawTraces(Canvas canvas, Size size, double opacity) {
    final paint = Paint()
      ..color = NuvoColors.blue.withValues(alpha: 0.15 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Scattered trace lines suggesting raw movement data.
    final traces = [
      [Offset(20, size.height * 0.7), Offset(60, size.height * 0.5), Offset(40, size.height * 0.3)],
      [Offset(80, size.height * 0.8), Offset(120, size.height * 0.4), Offset(100, size.height * 0.2)],
      [Offset(size.width * 0.4, size.height * 0.6), Offset(size.width * 0.6, size.height * 0.3), Offset(size.width * 0.5, size.height * 0.1)],
      [Offset(size.width * 0.6, size.height * 0.7), Offset(size.width * 0.8, size.height * 0.4), Offset(size.width - 40, size.height * 0.2)],
    ];

    for (final trace in traces) {
      final p = Path()..moveTo(trace[0].dx, trace[0].dy);
      for (var i = 1; i < trace.length; i++) {
        p.lineTo(trace[i].dx, trace[i].dy);
      }
      canvas.drawPath(p, paint);
    }
  }

  void _drawVerifiedSeal(Canvas canvas, Offset center, double t) {
    final radius = 18.0 * t;
    // Outer ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = NuvoColors.blue.withValues(alpha: 0.12 * t)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = NuvoColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * t,
    );
    // Check mark.
    if (t > 0.5) {
      final checkT = (t - 0.5) / 0.5;
      final checkPath = Path()
        ..moveTo(center.dx - 7, center.dy)
        ..lineTo(center.dx - 2, center.dy + 5)
        ..lineTo(center.dx + 7, center.dy - 5);
      canvas.drawPath(
        checkPath,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * checkT
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  // ── Network: Crew's shared current ─────────────────────────────────────────

  void _paintNetwork(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(size.width, size.height) * 0.35;

    // Connection lines from center to each marker.
    for (final m in markers) {
      final angle = -math.pi / 2 + (m.progress * 2 * math.pi);
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);

      // Pale connection line.
      final linePath = Path()
        ..moveTo(cx, cy)
        ..lineTo(x, y);
      canvas.drawPath(
        linePath,
        Paint()
          ..color = NuvoColors.blue.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Progress portion of the line.
      final progLine = Path()
        ..moveTo(cx, cy)
        ..lineTo(cx + (x - cx) * m.progress.clamp(0.0, 1.0), cy + (y - cy) * m.progress.clamp(0.0, 1.0));
      canvas.drawPath(
        progLine,
        Paint()
          ..color = NuvoColors.blue.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Avatar marker.
      _drawAvatarMarker(canvas, Offset(x, y), m);
    }

    // Central "you" node.
    canvas.drawCircle(Offset(cx, cy), 22, Paint()..color = NuvoColors.blue.withValues(alpha: 0.08));
    canvas.drawCircle(Offset(cx, cy), 16, Paint()..color = NuvoColors.blue);
    canvas.drawCircle(Offset(cx, cy), 16, Paint()..color = NuvoColors.surface..style = PaintingStyle.fill);
    canvas.drawCircle(
      Offset(cx, cy),
      16,
      Paint()
        ..color = NuvoColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  // ── Timeline: Profile's movement legacy ────────────────────────────────────

  void _paintTimeline(Canvas canvas, Size size) {
    final y = size.height / 2;
    final startX = 12.0;
    final endX = size.width - 12;

    // Full track.
    final path = Path()
      ..moveTo(startX, y)
      ..lineTo(endX, y);
    _drawTrack(canvas, path, NuvoColors.secondarySurface, 4);

    // Ticks.
    if (showTicks) _drawTicksOnPath(canvas, path, size);

    // Progress.
    final t = progress.clamp(0.0, 1.0);
    if (t > 0) {
      final progPath = Path()
        ..moveTo(startX, y)
        ..lineTo(startX + (endX - startX) * t, y);
      canvas.drawPath(
        progPath,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }

    // Milestone markers.
    for (final m in markers) {
      final x = startX + (endX - startX) * m.progress.clamp(0.0, 1.0);
      _drawTimelineMarker(canvas, Offset(x, y), m);
    }
  }

  // ── Shared drawing helpers ─────────────────────────────────────────────────

  void _drawTrack(Canvas canvas, Path path, Color color, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawProgress(Canvas canvas, Path path, double t, Color color, double width) {
    final metric = path.computeMetrics().first;
    final travelled = metric.extractPath(0, metric.length * t.clamp(0.0, 1.0));
    canvas.drawPath(
      travelled,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawTicks(Canvas canvas, Path path, Size size) {
    _drawTicksOnPath(canvas, path, size);
  }

  void _drawTicksOnPath(Canvas canvas, Path path, Size size) {
    final metric = path.computeMetrics().first;
    final tickPaint = Paint()
      ..color = NuvoColors.border
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    for (var i = 1; i < 4; i++) {
      final t = i / 4.0;
      final pos = metric.getTangentForOffset(metric.length * t)?.position;
      if (pos == null) continue;
      canvas.drawLine(
        pos.translate(0, -4),
        pos.translate(0, 4),
        tickPaint,
      );
    }
  }

  void _drawFinishBeacon(Canvas canvas, Path path, Size size) {
    final finish = _pointAt(path, 1);
    // Flag post.
    canvas.drawLine(
      finish.translate(0, -4),
      finish.translate(0, -22),
      Paint()
        ..color = NuvoColors.border
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    // Flag.
    final flag = Path()
      ..moveTo(finish.dx, finish.dy - 22)
      ..lineTo(finish.dx + 12, finish.dy - 18)
      ..lineTo(finish.dx, finish.dy - 14)
      ..close();
    canvas.drawPath(flag, Paint()..color = NuvoColors.navy);
  }

  void _drawCheckeredFinish(Canvas canvas, Offset top, Offset bottom) {
    const cellSize = 4.0;
    final height = (bottom.dy - top.dy).abs();
    final rows = (height / cellSize).round();
    for (var r = 0; r < rows; r++) {
      final y = top.dy + r * cellSize;
      final isDark = r % 2 == 0;
      canvas.drawRect(
        Rect.fromLTWH(top.dx, y, cellSize, cellSize),
        Paint()..color = isDark ? NuvoColors.navy : NuvoColors.surface,
      );
    }
  }

  void _drawMarkers(Canvas canvas, Path path, Size size) {
    for (final m in markers) {
      final p = _pointAt(path, m.progress.clamp(0.0, 1.0));
      _drawAvatarMarker(canvas, p, m);
    }
  }

  void _drawAvatarMarker(Canvas canvas, Offset pos, MotionMarker m) {
    if (m.isCurrentUser) {
      // Soft halo.
      canvas.drawCircle(pos, m.size / 2 + 5, Paint()..color = NuvoColors.blue.withValues(alpha: 0.12));
      // White ring.
      canvas.drawCircle(pos, m.size / 2 + 2, Paint()..color = NuvoColors.surface);
      // Blue ring.
      canvas.drawCircle(
        pos,
        m.size / 2,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.fill,
      );
    } else if (m.isLeader) {
      canvas.drawCircle(pos, m.size / 2 + 2, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(
        pos,
        m.size / 2,
        Paint()
          ..color = NuvoColors.gold
          ..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawCircle(pos, m.size / 2 + 1.5, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(
        pos,
        m.size / 2,
        Paint()
          ..color = NuvoColors.textMuted.withValues(alpha: 0.4)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pos,
        m.size / 2,
        Paint()
          ..color = NuvoColors.textMuted.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _drawTimelineMarker(Canvas canvas, Offset pos, MotionMarker m) {
    if (m.isCurrentUser || m.isLeader) {
      canvas.drawCircle(pos, 10, Paint()..color = NuvoColors.blue.withValues(alpha: 0.1));
      canvas.drawCircle(pos, 6, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(
        pos,
        5,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawCircle(pos, 5, Paint()..color = NuvoColors.surface);
      canvas.drawCircle(
        pos,
        4,
        Paint()
          ..color = NuvoColors.border
          ..style = PaintingStyle.fill,
      );
    }
  }

  Offset _pointAt(Path path, double t) {
    final metric = path.computeMetrics().first;
    return metric.getTangentForOffset(metric.length * t.clamp(0.0, 1.0))?.position ?? Offset.zero;
  }

  @override
  bool shouldRepaint(VerifiedMotionPainter old) =>
      old.progress != progress ||
      old.secondaryProgress != secondaryProgress ||
      old.transformPhase != transformPhase ||
      _markersChanged(old.markers);

  bool _markersChanged(List<MotionMarker> other) {
    if (markers.length != other.length) return true;
    for (var i = 0; i < markers.length; i++) {
      if (markers[i].progress != other[i].progress) return true;
    }
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VERIFIED MOTION PATH WIDGET
//
// Wraps the painter with animation and reduce-motion handling.
// ═══════════════════════════════════════════════════════════════════════════════

class VerifiedMotionPath extends StatefulWidget {
  const VerifiedMotionPath({
    super.key,
    required this.progress,
    required this.style,
    this.markers = const [],
    this.secondaryProgress,
    this.showTicks = true,
    this.showFinish = true,
    this.transformPhase = 0,
    this.height = 62,
  });

  final double progress;
  final MotionPathStyle style;
  final List<MotionMarker> markers;
  final double? secondaryProgress;
  final bool showTicks;
  final bool showFinish;
  final double transformPhase;
  final double height;

  @override
  State<VerifiedMotionPath> createState() => _VerifiedMotionPathState();
}

class _VerifiedMotionPathState extends State<VerifiedMotionPath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _progressAnim;
  late Animation<double> _transformAnim;
  double _currentProgress = 0;
  double _currentTransform = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _setupAnimations(widget.progress, widget.transformPhase);
    _controller.forward();
  }

  void _setupAnimations(double targetProgress, double targetTransform) {
    _progressAnim = Tween<double>(begin: _currentProgress, end: targetProgress)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _transformAnim = Tween<double>(begin: _currentTransform, end: targetTransform)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(VerifiedMotionPath old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress || old.transformPhase != widget.transformPhase) {
      _currentProgress = _progressAnim.value;
      _currentTransform = _transformAnim.value;
      _setupAnimations(widget.progress, widget.transformPhase);
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (reduceMotion) {
      return SizedBox(
        height: widget.height,
        child: CustomPaint(
          painter: VerifiedMotionPainter(
            progress: widget.progress,
            style: widget.style,
            markers: widget.markers,
            secondaryProgress: widget.secondaryProgress,
            showTicks: widget.showTicks,
            showFinish: widget.showFinish,
            transformPhase: widget.transformPhase,
          ),
          size: Size.infinite,
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: VerifiedMotionPainter(
            progress: _progressAnim.value,
            style: widget.style,
            markers: widget.markers,
            secondaryProgress: widget.secondaryProgress,
            showTicks: widget.showTicks,
            showFinish: widget.showFinish,
            transformPhase: _transformAnim.value,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIVE PROGRESS NUMBER
//
// Oversized numerical typography that transitions cleanly when values change.
// ═══════════════════════════════════════════════════════════════════════════════

class LiveProgressNumber extends StatefulWidget {
  const LiveProgressNumber({
    super.key,
    required this.current,
    required this.total,
    this.suffix,
    this.color,
    this.size = 46,
  });

  final int current;
  final int total;
  final String? suffix;
  final Color? color;
  final double size;

  @override
  State<LiveProgressNumber> createState() => _LiveProgressNumberState();
}

class _LiveProgressNumberState extends State<LiveProgressNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<int> _numberAnim;
  int _displayed = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _setupAnimation(widget.current);
    _controller.forward();
  }

  void _setupAnimation(int target) {
    _numberAnim = IntTween(begin: _displayed, end: target)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(LiveProgressNumber old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      _displayed = _numberAnim.value;
      _setupAnimation(widget.current);
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (reduceMotion) {
      return _buildNumber(widget.current);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _buildNumber(_numberAnim.value),
    );
  }

  Widget _buildNumber(int value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$value',
          style: AppTextStyles.number(
            widget.size,
            color: widget.color ?? NuvoColors.blue,
            weight: FontWeight.w800,
          ),
        ),
        Text(
          ' / ${widget.total}${widget.suffix != null ? ' ${widget.suffix}' : ''}',
          style: AppTextStyles.number(
            widget.size * 0.56,
            color: NuvoColors.navy,
            weight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NUVO HERO CARD
//
// The shared premium card container — white surface, fine border, soft shadow.
// ═══════════════════════════════════════════════════════════════════════════════

class NuvoHeroCard extends StatelessWidget {
  const NuvoHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.radius = 26,
    this.shadow = AppShadows.heroShadow,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final List<BoxShadow> shadow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: shadow,
      ),
      child: child,
    );

    if (onTap != null) {
      return PressableScale(onTap: onTap, child: card);
    }
    return card;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NUVO SECTION LABEL
//
// Consistent section header with a blue accent bar and optional action.
// ═══════════════════════════════════════════════════════════════════════════════

class NuvoSectionLabel extends StatelessWidget {
  const NuvoSectionLabel({
    super.key,
    required this.label,
    this.action,
    this.onAction,
  });

  final String label;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(width: 3, height: 13, color: NuvoColors.blue),
          const SizedBox(width: 9),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  action!,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NUVO STATUS CHIP
//
// Compact status indicator with semantic colors.
// ═══════════════════════════════════════════════════════════════════════════════

class NuvoStatusChip extends StatelessWidget {
  const NuvoStatusChip({
    super.key,
    required this.label,
    this.color = NuvoColors.blue,
    this.backgroundColor,
    this.icon,
    this.size = NuvoStatusChipSize.regular,
  });

  final String label;
  final Color color;
  final Color? backgroundColor;
  final IconData? icon;
  final NuvoStatusChipSize size;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? color.withValues(alpha: 0.08);
    final pad = size == NuvoStatusChipSize.small
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 11, vertical: 6);
    final fontSize = size == NuvoStatusChipSize.small ? 9.0 : 10.0;

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
}

enum NuvoStatusChipSize { small, regular }

// ═══════════════════════════════════════════════════════════════════════════════
// NUVO EMPTY STATE
//
// Intentional, useful empty state with a clear next action.
// ═══════════════════════════════════════════════════════════════════════════════

class NuvoEmptyState extends StatelessWidget {
  const NuvoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: NuvoColors.secondarySurface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: NuvoColors.blue, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: AppTextStyles.labelMedium.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.textMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          PressableScale(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              decoration: BoxDecoration(
                color: NuvoColors.blue,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                actionLabel,
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NUVO LOADING SKELETON
//
// Calm placeholder bars — no spinner, no shimmer. Stable for screenshots.
// ═══════════════════════════════════════════════════════════════════════════════

class NuvoSkeletonBar extends StatelessWidget {
  const NuvoSkeletonBar({
    super.key,
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: NuvoColors.disabledSurface,
        borderRadius: BorderRadius.circular(math.min(height / 2, 8)),
      ),
    );
  }
}

class NuvoSkeletonCard extends StatelessWidget {
  const NuvoSkeletonCard({
    super.key,
    required this.height,
    this.padding = 22,
  });

  final double height;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuvoSkeletonBar(width: 92, height: 18),
          const SizedBox(height: 18),
          NuvoSkeletonBar(width: 210, height: 26),
          const SizedBox(height: 10),
          NuvoSkeletonBar(width: 150, height: 44),
          const SizedBox(height: 22),
          const NuvoSkeletonBar(width: double.infinity, height: 7),
          const Spacer(),
          const NuvoSkeletonBar(width: double.infinity, height: 52),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NUVO PRIMARY ACTION
//
// The obvious contextual button. Compresses on press.
// ═══════════════════════════════════════════════════════════════════════════════

class NuvoPrimaryAction extends StatelessWidget {
  const NuvoPrimaryAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? NuvoColors.blue : NuvoColors.disabledSurface,
          borderRadius: BorderRadius.circular(15),
          boxShadow: enabled ? AppShadows.trackBlueGlowSubtle : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: enabled ? NuvoColors.white : NuvoColors.disabledText, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTextStyles.buttonLabel.copyWith(
                color: enabled ? NuvoColors.white : NuvoColors.disabledText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTEXT ACTION DOCK
//
// Compact, authored action area — prioritises the most relevant action.
// ═══════════════════════════════════════════════════════════════════════════════

class ContextActionDock extends StatelessWidget {
  const ContextActionDock({
    super.key,
    required this.primary,
    required this.secondary,
  });

  final DockAction primary;
  final List<DockAction> secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(flex: 2, child: _buildAction(primary, true)),
          const SizedBox(width: 10),
          for (var i = 0; i < secondary.length; i++) ...[
            Expanded(child: _buildAction(secondary[i], false)),
            if (i < secondary.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildAction(DockAction action, bool emphasised) {
    final enabled = action.onTap != null;
    final fg = !enabled
        ? NuvoColors.disabledText
        : emphasised
            ? NuvoColors.white
            : NuvoColors.navy;

    return PressableScale(
      onTap: action.onTap,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: !enabled
              ? NuvoColors.disabledSurface
              : emphasised
                  ? NuvoColors.blue
                  : NuvoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: emphasised ? null : Border.all(color: NuvoColors.border, width: 1),
          boxShadow: emphasised ? AppShadows.trackBlueGlowSubtle : AppShadows.card,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, size: 18, color: fg),
            if (emphasised) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Convenience factory for ContextActionDock actions.
DockAction dockAction(IconData icon, String label, {VoidCallback? onTap}) =>
    DockAction(icon: icon, label: label, onTap: onTap);

class DockAction {
  const DockAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRECISION LEADERBOARD ROW
//
// Refined ranking row with rank, avatar, name, score, and progress.
// ═══════════════════════════════════════════════════════════════════════════════

class PrecisionLeaderboardRow extends StatelessWidget {
  const PrecisionLeaderboardRow({
    super.key,
    required this.rank,
    required this.initials,
    required this.name,
    required this.score,
    this.photoUrl,
    this.isCurrentUser = false,
    this.progress,
    this.last = false,
  });

  final int rank;
  final String initials;
  final String name;
  final String score;
  final String? photoUrl;
  final bool isCurrentUser;
  final double? progress;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: NuvoColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: AppTextStyles.labelSmall.copyWith(
                color: isCurrentUser ? NuvoColors.blue : NuvoColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          NuvoAvatar(
            initials: initials,
            photoUrl: photoUrl,
            size: 30,
            bgColor: NuvoColors.secondarySurface,
            textColor: isCurrentUser ? NuvoColors.blue : NuvoColors.navy,
            borderColor: isCurrentUser ? NuvoColors.blue : Colors.transparent,
            borderWidth: isCurrentUser ? 1.5 : 0,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isCurrentUser ? 'You' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isCurrentUser ? NuvoColors.blue : NuvoColors.navy,
                fontWeight: isCurrentUser ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (progress != null) ...[
            SizedBox(
              width: 40,
              child: Text(
                '${(progress! * 100).round()}%',
                textAlign: TextAlign.right,
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            score,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VERIFIED ACTIVITY CARD
//
// Polished activity stream entry with typed icon and verification state.
// ═══════════════════════════════════════════════════════════════════════════════

class VerifiedActivityCard extends StatelessWidget {
  const VerifiedActivityCard({
    super.key,
    required this.actorName,
    required this.text,
    this.raceTitle,
    required this.timeLabel,
    required this.type,
    this.last = false,
  });

  final String actorName;
  final String text;
  final String? raceTitle;
  final String timeLabel;
  final String type;
  final bool last;

  (IconData, Color) get _mark => switch (type) {
        'proof_submitted' => (Icons.verified_rounded, NuvoColors.success),
        'finished' => (Icons.flag_rounded, NuvoColors.blue),
        'joined' => (Icons.person_add_rounded, NuvoColors.blue),
        'leader_changed' => (Icons.trending_up_rounded, NuvoColors.warning),
        _ => (Icons.schedule_rounded, NuvoColors.textMuted),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = _mark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: NuvoColors.border)),
      ),
      child: Row(
        children: [
          NuvoAvatar(
            initials: _initials(actorName),
            size: 34,
            bgColor: NuvoColors.secondarySurface,
            textColor: NuvoColors.navy,
            borderColor: Colors.transparent,
            borderWidth: 0,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(icon, size: 12, color: tint),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        [
                          if (raceTitle != null) raceTitle!,
                          timeLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACHIEVEMENT MEDALLION
//
// Collectible, authored achievement marker for the Profile timeline.
// ═══════════════════════════════════════════════════════════════════════════════

class AchievementMedallion extends StatelessWidget {
  const AchievementMedallion({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = NuvoColors.blue,
    this.earned = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: earned ? NuvoColors.surface : NuvoColors.disabledSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: earned ? color.withValues(alpha: 0.2) : NuvoColors.border,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: earned ? color.withValues(alpha: 0.08) : NuvoColors.border,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: earned ? color : NuvoColors.disabledText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.number(
              18,
              color: earned ? NuvoColors.navy : NuvoColors.disabledText,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: earned ? NuvoColors.textMuted : NuvoColors.disabledText,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
