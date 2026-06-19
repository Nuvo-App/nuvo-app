import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            // Brand mark — compact pill, no help icon
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: NuvoColors.navy,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Image.asset(AssetPaths.nuvoLogo),
                ),
                const SizedBox(width: 10),
                Text('Nuvo', style: AppTextStyles.titleLarge),
              ],
            ),
            const SizedBox(height: 36),

            // Hero text
            Text(
              'Compete on anything.\nWith anyone.',
              style: AppTextStyles.displayLarge.copyWith(
                color: NuvoColors.navy,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Pick a goal, pull in your crew, and race to the finish.',
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 32),

            const _RaceLoopCard(),
            const SizedBox(height: 28),

            // Primary CTA
            NuvoPrimaryButton(
              label: 'Get started',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: () => context.go('/onboarding/create-identity'),
            ),
            const SizedBox(height: 12),

            // Secondary CTA
            NuvoOutlineButton(
              label: 'I already have an account',
              expand: true,
              onPressed: () => context.go('/auth/email'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RaceLoopCard extends StatelessWidget {
  const _RaceLoopCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A07152B),
            blurRadius: 18,
            offset: Offset(8, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'START LINE',
            style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.blue),
          ),
          const SizedBox(height: 10),
          Text('Create race', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Pull in crew, submit proof, track progress, and climb the leaderboard.',
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}
