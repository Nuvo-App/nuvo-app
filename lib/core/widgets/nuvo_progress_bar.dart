import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class NuvoProgressBar extends StatelessWidget {
  const NuvoProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 5,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? NuvoColors.blue;
    final clamped = value.clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: clamped),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Container(
            height: height,
            color: NuvoColors.softBlue,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: animated,
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
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
