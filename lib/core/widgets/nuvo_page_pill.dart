import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'nuvo_motion.dart';

/// Pagination for any paged surface: the active slot is a wide filled pill,
/// inactive slots are small navy-outline circles. Shape and color animate
/// together on [NuvoMotion.select] so a swipe reads as the indicator
/// traveling, not repainting.
///
/// Pure indicator — it renders state, it never owns the PageController.
/// Reduced motion still animates (position/state changes are informative,
/// not decorative) but stays inside the standard select duration.
class NuvoPagePill extends StatelessWidget {
  const NuvoPagePill({
    super.key,
    required this.count,
    required this.selected,
  });

  final int count;
  final int selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: NuvoMotion.select,
            curve: NuvoMotion.settle,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == selected ? 20 : 6,
            height: i == selected ? 8 : 6,
            decoration: BoxDecoration(
              color:
                  i == selected ? NuvoColors.actionBlue : Colors.transparent,
              border: Border.all(
                color: context.themeColors.border,
                width: i == selected ? 1.5 : 1.25,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
