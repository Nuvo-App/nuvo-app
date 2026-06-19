import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Faint blue-tinted orb background — light theme version.
/// Used on pages that want a subtle ambient feel without heavy visuals.
class LightPageBackground extends StatelessWidget {
  const LightPageBackground({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: NuvoColors.page),
        Positioned(
          top: -80,
          right: -60,
          child: _Orb(
            size: 280,
            color: NuvoColors.blue.withValues(alpha: 0.055),
          ),
        ),
        Positioned(
          top: 320,
          left: -80,
          child: _Orb(
            size: 240,
            color: NuvoColors.blueSoft.withValues(alpha: 0.04),
          ),
        ),
        Positioned(
          bottom: 80,
          right: 20,
          child: _Orb(
            size: 200,
            color: NuvoColors.mint.withValues(alpha: 0.035),
          ),
        ),
        ?child,
      ],
    );
  }
}

/// Legacy alias — kept so any old references compile without changes.
@Deprecated('Use LightPageBackground instead')
class DreamBackground extends StatelessWidget {
  const DreamBackground({super.key});

  @override
  Widget build(BuildContext context) => const LightPageBackground();
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 60, spreadRadius: 10)],
      ),
    );
  }
}
