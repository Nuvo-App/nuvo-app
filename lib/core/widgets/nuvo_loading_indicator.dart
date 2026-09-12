import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Brand-colored loading indicator — replaces bare `CircularProgressIndicator()`
/// per the Nuvo App Design Guide's "no part of the app that doesn't feel
/// responsive or interactive... even simple loading screens should feel
/// thought out" rule. A plain spinner has no brand color and no personality;
/// this one pulses gently instead of just spinning flat.
class NuvoLoadingIndicator extends StatefulWidget {
  const NuvoLoadingIndicator({super.key, this.size = 32, this.color});

  final double size;
  final Color? color;

  @override
  State<NuvoLoadingIndicator> createState() => _NuvoLoadingIndicatorState();
}

class _NuvoLoadingIndicatorState extends State<NuvoLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? NuvoColors.blue;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final scale = 0.85 + 0.15 * (1 - (2 * t - 1).abs());
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CircularProgressIndicator(
              strokeWidth: widget.size / 10,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        );
      },
    );
  }
}
