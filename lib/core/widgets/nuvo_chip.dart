import 'package:flutter/material.dart';

import '../design/nuvo_preview_style.dart';
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
    final visual = NuvoVisualTheme.of(context);
    final accent = accentColor ?? visual.action;
    final bgColor = selected ? accent.withValues(alpha: 0.10) : visual.surface;
    final border = selected ? accent : visual.border;
    final textColor = selected ? accent : visual.ink;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: border, width: selected ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: textColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
