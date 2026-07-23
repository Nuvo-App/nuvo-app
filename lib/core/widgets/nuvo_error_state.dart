import 'package:flutter/material.dart';

import '../design/nuvo_preview_style.dart';
import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_button.dart';

class NuvoErrorState extends StatelessWidget {
  const NuvoErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: visual.surface,
                borderRadius: BorderRadius.circular(NuvoRadii.md),
                border: Border.all(color: NuvoColors.danger, width: 2),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 22,
                color: NuvoColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: AppTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: visual.mutedInk),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            NuvoOutlineButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
