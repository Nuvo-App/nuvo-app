import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import 'pressable_scale.dart';

/// Premium surface with quiet separation from the page.
class NuvoCard extends StatelessWidget {
  const NuvoCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevated = true,
    this.borderColor,
    this.borderWidth = 2,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool elevated;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    Widget card = Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(
          color: borderColor ?? c.border,
          width: borderWidth,
        ),
        boxShadow: elevated
            ? AppShadows.hardOffset(c.inkShadow, offset: const Offset(5, 5))
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return PressableScale(onTap: onTap, scale: 0.985, child: card);
    }
    return card;
  }
}

/// Compact card for secondary information.
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
