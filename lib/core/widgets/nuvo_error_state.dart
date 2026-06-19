import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 44,
              color: NuvoColors.muted,
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
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
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
