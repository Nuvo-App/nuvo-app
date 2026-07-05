import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';

/// One racer's marker on the [RaceRing] circumference.
class RingRacer {
  const RingRacer({
    required this.id,
    required this.initials,
    required this.progress,
    this.isCurrentUser = false,
    this.color,
    this.photoUrl,
  });

  final String id;
  final String initials;

  /// 0.0..1.0 progress toward the race goal — this is what places the
  /// marker on the ring. Must be real per-racer progress, never a guess.
  final double progress;
  final bool isCurrentUser;
  final Color? color;
  final String? photoUrl;
}

/// Pure geometry for the Race Ring's marker placement. 0% sits at the top
/// (12 o'clock) and position advances clockwise as progress increases:
/// angle = -90 + (progress * 360) degrees, matching the prototype's
/// `.ring-marker` math (cx=80, cy=80, r=58 at a 160x160 viewBox — scaled
/// here to whatever [radius]/[center] the widget is given).
Offset ringPointForProgress({
  required double progress,
  required Offset center,
  required double radius,
}) {
  final angleDegrees = -90 + progress.clamp(0.0, 1.0) * 360;
  final angleRadians = angleDegrees * (math.pi / 180);
  return Offset(
    center.dx + radius * math.cos(angleRadians),
    center.dy + radius * math.sin(angleRadians),
  );
}

/// The Arena's signature visual: a circular track showing your progress
/// toward the race goal as an animated arc, with every racer's real
/// progress plotted as a marker around the circumference — a literal
/// circular leaderboard, not a decorative ring.
class RaceRing extends StatefulWidget {
  const RaceRing({
    super.key,
    required this.progress,
    required this.centerValue,
    this.centerLabel,
    this.racers = const [],
    this.size = 160,
    this.strokeWidth = 10,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 1000),
  });

  /// Your own progress toward the goal, 0.0..1.0.
  final double progress;
  final String centerValue;
  final String? centerLabel;
  final List<RingRacer> racers;
  final double size;
  final double strokeWidth;
  final Duration delay;
  final Duration duration;

  @override
  State<RaceRing> createState() => _RaceRingState();
}

class _RaceRingState extends State<RaceRing> with SingleTickerProviderStateMixin {
  double _target = 0;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    // A few pulses to draw the eye, then settle — an indefinite repeat here
    // keeps a ticker alive on every mounted Race Ring for as long as the
    // screen is open, which adds up when several are on screen.
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true, count: 3);
    if (widget.delay == Duration.zero) {
      _target = widget.progress.clamp(0.0, 1.0);
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) setState(() => _target = widget.progress.clamp(0.0, 1.0));
      });
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RaceRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _target = widget.progress.clamp(0.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final radius = (widget.size / 2) - widget.strokeWidth - 6;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _target),
            duration: widget.duration,
            curve: Curves.easeOutCubic,
            builder: (context, animatedProgress, _) {
              return CustomPaint(
                size: Size.square(widget.size),
                painter: _RingPainter(
                  progress: animatedProgress,
                  strokeWidth: widget.strokeWidth,
                ),
              );
            },
          ),
          for (final racer in widget.racers)
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                final point = ringPointForProgress(
                  progress: racer.progress,
                  center: center,
                  radius: radius,
                );
                const markerSize = 26.0;
                return Positioned(
                  left: point.dx - markerSize / 2,
                  top: point.dy - markerSize / 2,
                  child: SizedBox(
                    width: markerSize,
                    height: markerSize,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (racer.isCurrentUser)
                          Transform.scale(
                            scale: 1.0 + _pulseCtrl.value * 0.45,
                            child: Container(
                              width: markerSize,
                              height: markerSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: NuvoColors.blue.withValues(
                                  alpha: 0.35 * (1 - _pulseCtrl.value),
                                ),
                              ),
                            ),
                          ),
                        NuvoAvatar(
                          initials: racer.initials,
                          size: markerSize,
                          photoUrl: racer.photoUrl,
                          bgColor: racer.color ?? nuvoAvatarColorFor(racer.id),
                          textColor: Colors.white,
                          borderColor: Colors.white,
                          borderWidth: 2,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.centerValue, style: AppTextStyles.number(widget.size * 0.26)),
              if (widget.centerLabel != null)
                Text(widget.centerLabel!, style: AppTextStyles.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.strokeWidth});

  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = NuvoColors.trackBg
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final fill = Paint()
      ..color = NuvoColors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, progress * 2 * math.pi, false, fill);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.strokeWidth != strokeWidth;
}
