import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';

/// Clean white surface card with subtle shadow — light theme.
class NuvoCard extends StatelessWidget {
  const NuvoCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevated = false,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool elevated;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.card,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: borderColor ?? NuvoColors.border, width: 1),
        boxShadow: elevated ? AppShadows.card : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }
    return card;
  }
}

/// Compact bento-style card — tighter padding, used for stat tiles.
class NuvoBentoCard extends StatelessWidget {
  const NuvoBentoCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoCard(
      padding: const EdgeInsets.all(16),
      elevated: true,
      onTap: onTap,
      child: child,
    );
  }
}
