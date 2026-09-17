import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_button.dart';

class NuvoErrorState extends StatelessWidget {
  const NuvoErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = 'Something went wrong',
    this.icon = Icons.wifi_off_rounded,
    this.retryLabel = 'Try again',
  });

  final String title;
  final String message;
  final IconData icon;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
                color: NuvoColors.white,
                borderRadius: BorderRadius.circular(NuvoRadii.md),
                border: Border.all(color: NuvoColors.danger, width: 2),
              ),
              child: Icon(icon, size: 22, color: NuvoColors.danger),
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            NuvoOutlineButton(label: retryLabel, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// Compact connection banner for a screen that already has cached content
/// visible — the offline signal should not replace what's on screen, just
/// sit above it. Deliberately quiet (no red/danger): the data on screen is
/// still real and valid, it just might not be current.
class NuvoOfflineBanner extends StatelessWidget {
  const NuvoOfflineBanner({
    super.key,
    required this.onRetry,
    this.message = 'No connection — showing saved data.',
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NuvoColors.panel,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: NuvoBorders.quiet,
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: NuvoColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRetry,
            behavior: HitTestBehavior.opaque,
            child: Text(
              'Try again',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
