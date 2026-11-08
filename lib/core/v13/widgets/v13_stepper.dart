import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_pressable.dart';

/// Minus / value / plus stepper for goal pickers and manual proof counts.
class V13Stepper extends StatelessWidget {
  const V13Stepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.step = 1,
    this.semanticLabel,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final canDown = value - step >= min;
    final canUp = value + step <= max;
    return Semantics(
      label: semanticLabel ?? 'Value $value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove,
            enabled: canDown,
            semanticLabel: 'Decrease',
            onTap: () => onChanged(value - step),
          ),
          SizedBox(
            width: 64,
            child: Center(child: Text('$value', style: V13.number)),
          ),
          _StepButton(
            icon: Icons.add,
            enabled: canUp,
            semanticLabel: 'Increase',
            onTap: () => onChanged(value + step),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    final radius = BorderRadius.circular(size / 2);
    return V13Pressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      shadow: enabled ? V13.shadow3 : null,
      borderRadius: radius,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? V13.card : V13.bg,
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: Icon(icon, size: 18, color: enabled ? V13.navy : V13.muted),
      ),
    );
  }
}
