import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_motion.dart';

/// Scannable icon + label(+sub) metadata chip — the shared primitive for the
/// "who / how much" facts beneath a screen's hero (race target, participant
/// count, crew size, etc.). Never render this information as loose gray text.
class NuvoMetaItem extends StatelessWidget {
  const NuvoMetaItem({
    super.key,
    required this.icon,
    required this.label,
    this.sub,
    this.iconColor = NuvoColors.actionBlue,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? sub;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.themeColors.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: context.themeColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.themeColors.inkMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return NuvoPressable(onTap: onTap, haptic: false, child: chip);
  }
}

/// A centered, wrapping row of [NuvoMetaItem]s — the standard "scannable
/// facts beneath the hero" row shared by the Race review and Crew screens.
class NuvoMetaRow extends StatelessWidget {
  const NuvoMetaRow({
    super.key,
    required this.items,
    this.alignment = WrapAlignment.center,
  });

  final List<NuvoMetaItem> items;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      spacing: 8,
      runSpacing: 8,
      children: items,
    );
  }
}
