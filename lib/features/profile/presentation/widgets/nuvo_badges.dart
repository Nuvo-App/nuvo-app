import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/progression_models.dart';

/// Server metadata `icon` key → glyph. The server stores a stable
/// identifier; the mapping lives here so badge art stays inside Nuvo's
/// icon language.
IconData nuvoBadgeIconFor(String? icon) {
  switch (icon) {
    case 'flag':
      return Icons.flag_rounded;
    case 'bolt':
      return Icons.bolt_rounded;
    case 'flame':
      return Icons.local_fire_department_rounded;
    case 'target':
      return Icons.adjust_rounded;
    case 'medal':
      return Icons.military_tech_rounded;
    case 'trophy':
      return Icons.emoji_events_rounded;
    case 'crown':
      return Icons.workspace_premium_rounded;
    case 'star':
      return Icons.star_rounded;
    default:
      return Icons.emoji_events_rounded;
  }
}

/// A badge as a physical disc — earned badges carry color (blue standard,
/// gold milestone) and a hard offset shadow; locked badges are quiet,
/// muted, and show the level they ask for underneath.
class NuvoBadgeDisc extends StatelessWidget {
  const NuvoBadgeDisc({
    super.key,
    required this.badge,
    this.size = 56,
    this.showRequirement = false,
  });

  final NuvoBadge badge;
  final double size;
  final bool showRequirement;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final iconSize = size * 0.46;
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: badge.unlocked
            ? (badge.isMilestone ? NuvoColors.gold : NuvoColors.blue)
            : c.panelLight,
        border: Border.all(
          color: badge.unlocked ? c.inkShadow : c.border,
          width: 2,
        ),
        boxShadow: badge.unlocked
            ? [
                BoxShadow(
                  color: c.inkShadow,
                  offset: const Offset(3, 3),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Icon(
          badge.unlocked
              ? nuvoBadgeIconFor(badge.icon)
              : Icons.lock_outline_rounded,
          size: iconSize,
          color: badge.unlocked ? NuvoColors.white : c.inkDim,
        ),
      ),
    );

    if (!showRequirement) return disc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        disc,
        const SizedBox(height: 6),
        Text(
          badge.unlocked ? 'LEVEL ${badge.requiredLevel}' : 'LVL ${badge.requiredLevel}',
          style: AppTextStyles.labelUppercase(
            9,
            color: badge.unlocked ? c.inkSubtle : c.inkDim,
          ).copyWith(color: badge.unlocked ? c.inkSubtle : c.inkDim),
        ),
      ],
    );
  }
}
