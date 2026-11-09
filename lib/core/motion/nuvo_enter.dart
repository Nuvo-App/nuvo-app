import 'package:flutter/widgets.dart';

import 'nuvo_motion.dart';

/// The onboarding entrance — spring from y+28, opacity 0, staggered by
/// [index] (70 ms each, capped at 5). Plays once per mounted element.
///
/// Reduce-motion: no rise, just the 200 ms cross-fade.
class NuvoEnter extends StatefulWidget {
  const NuvoEnter({super.key, required this.child, this.index = 0});

  final Widget child;

  /// Stagger slot — the delay is [NuvoMotion.staggerStep] × index, capped at
  /// [NuvoMotion.staggerMax] so a long list never waits on its tail.
  final int index;

  @override
  State<NuvoEnter> createState() => _NuvoEnterState();
}

class _NuvoEnterState extends State<NuvoEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.enter,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NuvoMotion.reduceMotionOf(context)) {
      // Cross-fade only — the 200 ms fade is the one surviving transition.
      _ctrl.duration = NuvoMotion.reduceMotionFade;
      _ctrl.forward();
      return;
    }
    Future.delayed(NuvoMotion.staggerFor(widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, c) {
        final t = reduce
            ? _ctrl.value.clamp(0.0, 1.0)
            : NuvoMotion.spring.transform(_ctrl.value.clamp(0.0, 1.0));
        final dy = reduce ? 0.0 : NuvoMotion.enterOffsetY * (1 - t);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, dy), child: c),
        );
      },
    );
  }
}
