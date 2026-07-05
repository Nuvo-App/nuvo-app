import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

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

/// Progress bar that animates smoothly from 0 → [value] (after an optional
/// start [delay]), then keeps a continuous subtle shimmer sweep across the
/// filled portion even at rest (matches the prototype's `.lb-bar-fill::after`
/// shimmer).
class AnimatedProgressBar extends StatefulWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 5.0,
    this.duration = const Duration(milliseconds: 900),
    this.delay = Duration.zero,
    this.enableShimmer = true,
  });

  final double value;
  final Color? color;
  final double height;
  final Duration duration;
  final Duration delay;
  final bool enableShimmer;

  @override
  State<AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<AnimatedProgressBar> {
  double _target = 0;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _target = widget.value.clamp(0.0, 1.0);
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) setState(() => _target = widget.value.clamp(0.0, 1.0));
      });
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _target = widget.value.clamp(0.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.color ?? NuvoColors.blue;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: Container(
        height: widget.height,
        color: NuvoColors.trackBg,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _target),
          duration: widget.duration,
          curve: Curves.easeOut,
          builder: (context, progress, child) {
            final bar = Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(widget.height),
              ),
            );
            return FractionallySizedBox(
              widthFactor: progress,
              child: widget.enableShimmer && progress > 0
                  ? Shimmer.fromColors(
                      baseColor: fill,
                      highlightColor: Colors.white.withValues(alpha: 0.55),
                      period: const Duration(milliseconds: 2600),
                      loop: 3,
                      child: bar,
                    )
                  : bar,
            );
          },
        ),
      ),
    );
  }
}
