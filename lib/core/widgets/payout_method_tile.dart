import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Payout method row — disabled "Connect" button with "Coming soon" label.
/// Real-money payouts are not yet implemented.
class PayoutMethodTile extends StatelessWidget {
  const PayoutMethodTile({
    super.key,
    required this.name,
    required this.icon,
    this.iconColor,
    this.isConnected = false,
  });

  final String name;
  final IconData icon;
  final Color? iconColor;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NuvoColors.sectionBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: iconColor ?? NuvoColors.navy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(
                  isConnected ? 'Connected' : 'Not connected',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isConnected ? NuvoColors.mint : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isConnected)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: NuvoColors.mint.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'Connected',
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.mint,
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: NuvoColors.border,
                      ),
                    ),
                    child: Text(
                      'Connect',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Coming soon',
                  style: AppTextStyles.labelSmall,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
