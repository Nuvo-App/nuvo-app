import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'nuvo_motion.dart';

/// Idle float — hero cards, avatar tokens and badges only, never text or
/// buttons.
///
/// Spec: "translateY sine ±6px, period 3.2s, random phase 0–1.6s, rotation
/// ±1.2deg". Reduce-motion: the float never runs — the child renders still.
class NuvoFloat extends StatefulWidget {
  const NuvoFloat({super.key, required this.child, this.phase});

  final Widget child;

  /// Phase offset in seconds inside the 0–[NuvoMotion.floatPhaseMax] window.
  /// Null picks a deterministic pseudo-random phase per mounted instance.
  final double? phase;

  @override
  State<NuvoFloat> createState() => _NuvoFloatState();
}

class _NuvoFloatState extends State<NuvoFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.floatPeriod,
  );
  late final double _phase =
      widget.phase ??
      (math.Random().nextDouble() * NuvoMotion.floatPhaseMax) /
          (NuvoMotion.floatPeriod.inMilliseconds / 1000.0);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NuvoMotion.reduceMotionOf(context)) {
      _ctrl.value = 0;
      return;
    }
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, c) {
        final angle = (_ctrl.value + _phase) * 2 * math.pi;
        final dy = math.sin(angle) * NuvoMotion.floatAmplitude;
        final turns =
            math.sin(angle + math.pi / 2) * NuvoMotion.floatRotationDeg / 360;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(angle: turns * 2 * math.pi, child: c),
        );
      },
    );
  }
}
