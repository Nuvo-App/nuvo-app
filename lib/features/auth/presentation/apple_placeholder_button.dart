import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class ApplePlaceholderButton extends StatelessWidget {
  const ApplePlaceholderButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Opacity(
        opacity: 0.4,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: NuvoColors.navy,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apple, color: NuvoColors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Continue with Apple',
                style: AppTextStyles.labelLarge.copyWith(
                  color: NuvoColors.white,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: NuvoColors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Soon',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
