import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'nuvo_character_painter.dart';

/// Movement-specific key-pose data for the pre-verification character demo.
///
/// Contains the ordered key poses that describe one full cycle of the
/// movement, plus the loop duration. The generic [NuvoMovementAnimation]
/// widget interpolates between these poses and renders them with
/// [NuvoCharacterPainter].
class MovementDemo {
  const MovementDemo({
    required this.poses,
    required this.duration,
  });

  /// Ordered key poses for one complete movement cycle.
  /// The animation interpolates from poses[0] → poses[1] → ... → poses[last]
  /// and then loops back to poses[0].
  final List<NuvoCharacterPose> poses;

  /// Duration of one full cycle.
  final Duration duration;

  /// Interpolate across all key poses given a [t] in 0–1.
  /// Uses ease-in-out sine for natural movement.
  NuvoCharacterPose poseAt(double t) {
    final segmentCount = poses.length - 1;
    if (segmentCount <= 0) return poses.first;
    final scaled = t * segmentCount;
    final idx = scaled.floor().clamp(0, segmentCount - 1);
    final localT = scaled - idx;
    final eased = _easeInOutSine(localT);
    return NuvoCharacterPose.lerp(poses[idx], poses[idx + 1], eased);
  }

  static double _easeInOutSine(double t) => 0.5 * (1 - math.cos(math.pi * t));
}

/// A widget that displays an animated illustrated Nuvo character performing
/// a movement described by a [MovementDemo]. The animation loops continuously.
///
/// This is the generic renderer — it contains no movement-specific logic.
/// All movement knowledge lives in the [MovementDemo] data passed to it.
class NuvoMovementAnimation extends StatefulWidget {
  const NuvoMovementAnimation({
    super.key,
    required this.demo,
    this.bodyColor = NuvoColors.navy,
    this.accentColor = NuvoColors.blue,
    this.outlineColor = Colors.transparent,
    this.outlineWidth = 0,
  });

  final MovementDemo demo;
  final Color bodyColor;
  final Color accentColor;
  final Color outlineColor;
  final double outlineWidth;

  @override
  State<NuvoMovementAnimation> createState() => _NuvoMovementAnimationState();
}

class _NuvoMovementAnimationState extends State<NuvoMovementAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.demo.duration,
    )..repeat();
  }

  @override
  void didUpdateWidget(NuvoMovementAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.demo.duration != widget.demo.duration) {
      _controller.duration = widget.demo.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pose = widget.demo.poseAt(_controller.value);
        final inset = math.max(8.0, widget.outlineWidth + 4.0);
        return Padding(
          padding: EdgeInsets.all(inset),
          child: CustomPaint(
            painter: NuvoCharacterPainter(
              pose: pose,
              bodyColor: widget.bodyColor,
              accentColor: widget.accentColor,
              outlineColor: widget.outlineColor,
              outlineWidth: widget.outlineWidth,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}
