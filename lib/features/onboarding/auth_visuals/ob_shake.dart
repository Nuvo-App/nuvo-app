import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/motion/motion.dart';

/// Horizontal error shake: [NuvoMotion.shakeDistance] px, [count] swings
/// over [NuvoMotion.shake]. Call `shakeKey.currentState!.shake()`. Reduce
/// motion skips the movement entirely.
class ObShake extends StatefulWidget {
  const ObShake({super.key, required this.child, this.count = 2});

  final Widget child;
  final int count;

  @override
  State<ObShake> createState() => ObShakeState();
}

class ObShakeState extends State<ObShake> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.shake,
  );

  void shake() {
    if (!mounted || NuvoMotion.reduceMotionOf(context)) return;
    _ctrl.forward(from: 0);
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
      builder: (context, child) {
        final t = _ctrl.value;
        final dx =
            math.sin(t * math.pi * 2 * widget.count) *
            NuvoMotion.shakeDistance *
            (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}
