import 'package:flutter/material.dart';

import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_button.dart';

/// Standard confirm dialog: a 2d [NuvoTertiaryButton] "Cancel" paired with a
/// 3d [NuvoDangerButton] or [NuvoSuccessButton] confirm — the exact
/// low-emphasis/high-emphasis split the design guide asks for, applied at
/// dialog scale. Replaces the raw `TextButton` pairs previously hand-rolled
/// in profile, edit-profile, and race-settings confirm dialogs.
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
  return showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.titleLarge),
            const SizedBox(height: 10),
            Text(message, style: AppTextStyles.bodyMedium),
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
}
