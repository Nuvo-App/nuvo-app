import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_button.dart';
import 'nuvo_motion.dart';

/// Standard confirm dialog: a 2d [NuvoTertiaryButton] "Cancel" paired with a
/// 3d [NuvoDangerButton] or [NuvoSuccessButton] confirm — the exact
/// low-emphasis/high-emphasis split the design guide asks for, applied at
/// dialog scale. Replaces the raw `TextButton` pairs previously hand-rolled
/// in profile, edit-profile, and race-settings confirm dialogs.
///
/// Motion contract (docs/ui/NUVO_PLAY_SYSTEM.md §13.1): the scrim dims
/// quickly, the dialog rises ~20px and scales 0.96→1 in 180ms on
/// [NuvoMotion.settle] — serious arrival, never a game-reward bounce.
/// Reduced motion collapses to a plain fade. Chrome is Nuvo's: navy
/// outline + hard offset shadow, not generic Material.
///
/// Returns `true` if confirmed, `false`/`null` if cancelled or dismissed.
Future<bool?> showNuvoConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: context.themeColors.inkShadow.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, secondary, child) {
      if (MediaQuery.disableAnimationsOf(context)) {
        return FadeTransition(opacity: animation, child: child);
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: NuvoMotion.settle,
      );
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0)
              .animate(curved), child: child),
        ),
      );
    },
    pageBuilder: (context, animation, secondary) {
      final c = context.themeColors;
      return Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(NuvoRadii.lg),
              border: Border.all(color: c.border, width: 2),
              boxShadow: AppShadows.hardOffset(
                c.inkShadow,
                offset: const Offset(5, 5),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleLarge.copyWith(
                    color: c.ink,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                message,
                style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: NuvoTertiaryButton(
                      label: cancelLabel,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: destructive
                        ? NuvoDangerButton(
                            label: confirmLabel,
                            solid: true,
                            onPressed: () => Navigator.of(context).pop(true),
                          )
                        : NuvoSuccessButton(
                            label: confirmLabel,
                            solid: true,
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    },
  );
}
