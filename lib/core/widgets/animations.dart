import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';

/// Fades and slides a widget up from below into its final position.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 400),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return child
        .animate(delay: delay)
        .fade(duration: duration, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: duration, curve: Curves.easeOut);
  }
}

/// Adds a tactile press-to-scale effect using [Listener] so inner tap handlers
/// still fire normally through the gesture arena.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}

/// Progress bar that animates smoothly from 0 → [value] when first built.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 5.0,
    this.duration = const Duration(milliseconds: 900),
  });

  final double value;
  final Color? color;
  final double height;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? NuvoColors.blue;
    final clamped = value.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: NuvoColors.sectionBlue,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: clamped),
          duration: duration,
          curve: Curves.easeOut,
          builder: (context, progress, child) => FractionallySizedBox(
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
