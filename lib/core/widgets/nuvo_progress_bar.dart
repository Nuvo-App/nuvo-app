import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Thin progress bar — blue fill on light-blue track.
class NuvoProgressBar extends StatelessWidget {
  const NuvoProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 5,
  });

  /// Progress fraction — clamped to [0, 1].
  final double value;

  /// Fill color. Defaults to [NuvoColors.blue].
  final Color? color;

  final double height;

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
        child: FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(height),
            ),
          ),
        ),
      ),
    );
  }
}
