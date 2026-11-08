import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// Number display that pops (scale overshoot) when its value changes —
/// ranks, scores, counts.
class V13NumberPop extends StatefulWidget {
  const V13NumberPop({
    super.key,
    required this.value,
    this.style,
    this.format,
    this.peak = 0.28,
  });

  final num value;

  /// Defaults to [V13.number].
  final TextStyle? style;

  /// Custom formatter — defaults to the raw value.
  final String Function(num value)? format;

  /// Fractional scale at the pop's peak.
  final double peak;

  @override
  State<V13NumberPop> createState() => _V13NumberPopState();
}

class _V13NumberPopState extends State<V13NumberPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: V13Motion.fast,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant V13NumberPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward(from: 0);
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
        // Sine pop: 1 → peak → 1 over the duration.
        final scale = 1 + widget.peak * math.sin(math.pi * _ctrl.value);
        return Transform.scale(scale: scale, child: child);
      },
      child: Text(
        widget.format?.call(widget.value) ?? '${widget.value}',
        style: widget.style ?? V13.number,
      ),
    );
  }
}
