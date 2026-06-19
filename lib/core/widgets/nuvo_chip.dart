import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Pill chip used for category filters and tags — light theme.
class NuvoChip extends StatelessWidget {
  const NuvoChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.accentColor,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? NuvoColors.blue;
    final bgColor = selected ? NuvoColors.bluePale : NuvoColors.sectionBlue;
    final borderColor = selected
        ? accent.withValues(alpha: 0.35)
        : NuvoColors.border;
    final textColor = selected ? accent : NuvoColors.muted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(color: textColor),
        ),
      ),
    );
  }
}
