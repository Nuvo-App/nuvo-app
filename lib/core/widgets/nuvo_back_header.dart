import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_motion.dart';

/// Lightweight standalone-page top bar: a quiet navy arrow (44×44 hit target,
/// press fade — not a shadowed card) beside a headline-size title that owns
/// the remaining width in one stable row. Used by detail/settings pages
/// (My Nuvo, Notification Settings) where the tab-level `screenTitle` scale
/// and the heavy `NuvoBackButton` collide.
class NuvoBackHeader extends StatelessWidget {
  const NuvoBackHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: NuvoPressable(
            onTap: onBack,
            scale: 0.94,
            haptic: false,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.arrow_back_rounded,
                color: NuvoColors.navy,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headlineMedium,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}
