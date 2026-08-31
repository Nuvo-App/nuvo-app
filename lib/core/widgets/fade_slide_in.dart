import 'package:flutter/material.dart';

/// Entrance animation: fades in while sliding up and scaling up very slightly.
/// Use on any widget that should "materialize" when it first appears on screen.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 20.0,
  });

  final Widget child;
  final Duration delay;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 560),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - value)),
            child: Transform.scale(
              scale: 0.97 + 0.03 * value,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
