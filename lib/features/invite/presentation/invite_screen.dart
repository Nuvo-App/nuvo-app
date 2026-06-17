import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/gradient_button.dart';

class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key});

  static const _mockLink = 'nuvo.app/c/aBc123';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/arena'),
        ),
        title: const Text('Share Challenge'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          children: [
            const Spacer(),
            const _ChallengeInviteCard(),
            const SizedBox(height: 40),
            const _LinkRow(link: _mockLink),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Share Challenge',
              icon: Icons.share_rounded,
              expand: true,
              onPressed: () {},
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Link'),
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: _mockLink));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied!')),
                );
              },
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _ChallengeInviteCard extends StatelessWidget {
  const _ChallengeInviteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: AppGradients.brand,
        boxShadow: AppShadows.brandGlow(intensity: 0.8),
      ),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          color: AppColors.surface,
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppGradients.hot,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '🔥 CHALLENGE',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const Spacer(),
                Text('Nuvo', style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.electricBlue,
                )),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Shiv challenged you:',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Who can complete 100 pushups first?',
              style: AppTextStyles.headlineLarge,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: AppColors.neonMint, size: 20),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Prize Pool',
                          style: AppTextStyles.labelSmall),
                      Text('\$50',
                          style: AppTextStyles.headlineMedium.copyWith(
                              color: AppColors.neonMint)),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Entry',
                          style: AppTextStyles.labelSmall),
                      Text('\$25',
                          style: AppTextStyles.titleLarge),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link});
  final String link;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.link_rounded,
              color: AppColors.electricBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              link,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
