import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';
import 'v13_pressable.dart';

/// Settings toggle — blue when on, white when off, the knob slides on the
/// v13 spring.
class V13Toggle extends StatelessWidget {
  const V13Toggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  static const double _width = 52;
  static const double _height = 32;
  static const double _knob = 24;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: V13Pressable(
        onTap: () => onChanged(!value),
        pressDepth: 2,
        semanticLabel: semanticLabel,
        child: Container(
          width: _width,
          height: _height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? V13.blue : V13.card,
            borderRadius: BorderRadius.circular(V13.radiusPill),
            border: Border.all(color: V13.navy, width: V13.outline),
          ),
          child: AnimatedAlign(
            duration: reduce ? Duration.zero : V13Motion.fast,
            curve: V13Motion.spring,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: _knob,
              height: _knob,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: V13.card,
                border: Border.all(color: V13.navy, width: V13.outline),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
