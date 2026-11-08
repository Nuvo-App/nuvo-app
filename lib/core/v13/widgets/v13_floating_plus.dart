import 'package:flutter/material.dart';

import '../tokens.dart';

/// The "+N" that floats up and fades after logging a proof. Plays once on
/// mount; [onDone] fires when the float settles so callers can remove it.
class V13FloatingPlus extends StatefulWidget {
  const V13FloatingPlus({
    super.key,
    required this.value,
    this.color = V13.blue,
    this.duration = const Duration(milliseconds: 950),
    this.onDone,
  });

  /// Rendered as "+N".
  final int value;
  final Color color;
  final Duration duration;
  final VoidCallback? onDone;

  @override
  State<V13FloatingPlus> createState() => _V13FloatingPlusState();
}

class _V13FloatingPlusState extends State<V13FloatingPlus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onDone?.call(),
      );
    } else {
      _ctrl.forward().then((_) => widget.onDone?.call());
    }
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
      builder: (context, child) {
        final t = _ctrl.value;
        final rise = -38 * Curves.easeOutCubic.transform(t);
        final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(0, rise), child: child),
        );
      },
      child: Text(
        '+${widget.value}',
        style: V13.numberSm.copyWith(color: widget.color),
        semanticsLabel: 'plus ${widget.value}',
      ),
    );
  }
}
