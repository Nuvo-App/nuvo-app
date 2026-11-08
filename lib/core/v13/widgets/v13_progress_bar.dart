import 'package:flutter/material.dart';

import '../tokens.dart';

/// Progress toward the finish line — navy fill on a white track, both
/// wrapped in the navy outline. Value changes animate with a smooth fill.
class V13ProgressBar extends StatelessWidget {
  const V13ProgressBar({
    super.key,
    required this.value,
    this.height = 18,
    this.color = V13.navy,
    this.trackColor = V13.card,
    this.animate = true,
    this.semanticLabel,
  });

  /// 0.0–1.0; clamped.
  final double value;
  final double height;

  /// Fill color — navy by default ("navy fill on a white track").
  final Color color;
  final Color trackColor;

  /// Animate width when [value] changes (default on).
  final bool animate;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: semanticLabel ?? 'Progress ${(target * 100).round()} percent',
      child: Container(
        width: double.infinity,
        height: height,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(V13.radiusPill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: target),
            duration: animate && !reduce
                ? const Duration(milliseconds: 600)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => FractionallySizedBox(
              widthFactor: t,
              alignment: Alignment.centerLeft,
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
  }
}
