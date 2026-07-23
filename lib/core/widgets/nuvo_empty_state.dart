import 'package:flutter/material.dart';

import '../design/nuvo_preview_style.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_button.dart';

class NuvoEmptyState extends StatelessWidget {
  const NuvoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback? onCta;

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
                border: Border.all(color: visual.border),
              ),
              child: Icon(icon, size: 22, color: visual.action),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: AppTextStyles.bodyMedium.copyWith(color: visual.mutedInk),
              textAlign: TextAlign.center,
            ),
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 24),
              NuvoPrimaryButton(
                label: ctaLabel!,
                small: true,
                onPressed: onCta,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
