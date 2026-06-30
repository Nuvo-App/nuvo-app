import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class NuvoProgressBar extends StatelessWidget {
  const NuvoProgressBar({
    super.key,
    required this.value,
    this.color,
    this.trackColor,
    this.height = 6.0,
    this.gradient,
  });

  final double value;
  final Color? color;
  final Color? trackColor;
  final double height;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final effectiveGradient =
        gradient ??
        LinearGradient(
          colors: [
            color ?? NuvoColors.blue,
            (color ?? NuvoColors.blue).withValues(alpha: 0.75),
          ],
        );
    final clamped = value.clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: clamped),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Container(
            height: height,
            color: trackColor ?? NuvoColors.softBlue,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: animated,
              child: Container(
                decoration: BoxDecoration(
                  gradient: effectiveGradient,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
