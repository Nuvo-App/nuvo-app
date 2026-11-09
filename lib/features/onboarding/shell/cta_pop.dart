import 'package:flutter/widgets.dart';

import '../../../core/motion/motion.dart';

/// Springs the CTA from 94% to 100% each time it turns from disabled to
/// enabled ("the button just woke up"). Silent on first build and under
/// reduce-motion.
class CtaPop extends StatefulWidget {
  const CtaPop({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<CtaPop> createState() => _CtaPopState();
}

class _CtaPopState extends State<CtaPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: NuvoMotion.springDuration,
    value: 1,
  );

  @override
  void didUpdateWidget(CtaPop old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !NuvoMotion.reduceMotionOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Transform.scale(
        scale: 0.94 + 0.06 * NuvoMotion.spring.transform(_c.value),
        child: child,
      ),
    );
  }
}
