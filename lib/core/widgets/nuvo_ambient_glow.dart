import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Ambient background glow built entirely from [NuvoColors.blue] at varying
/// alpha — one hue, several opacities. Replaces the ad-hoc off-palette
/// blue-family gradients (`#618DDE`/`#6E9FF0`/`#79A8FF`/`#C5D9FA`/`#3F83FF`)
/// that splash and the welcome race-builder screen each hand-rolled
/// separately, per the design guide's "4-5 colors used for almost
/// everything" rule — a glow effect doesn't need a second palette to read as
/// atmospheric depth.
class NuvoAmbientGlow extends StatelessWidget {
  const NuvoAmbientGlow({
    super.key,
    this.alignment = Alignment.topCenter,
    this.radius = 0.9,
  });

  final Alignment alignment;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: alignment,
            radius: radius,
            colors: [
              NuvoColors.blue.withValues(alpha: 0.16),
              NuvoColors.blue.withValues(alpha: 0.07),
              NuvoColors.blue.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}
