import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';

class ProofScreen extends StatelessWidget {
  const ProofScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.navy,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => safePopOrGo(context, '/arena'),
                icon: const Icon(Icons.arrow_back_rounded),
                color: NuvoColors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Submit proof',
              style: AppTextStyles.displayMedium.copyWith(
                color: NuvoColors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Manual proof is active for this race. AI proof check is coming soon.',
              style: AppTextStyles.bodyLarge.copyWith(
                color: NuvoColors.softBlue,
              ),
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: NuvoColors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: NuvoColors.blue, width: 1.4),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.fact_check_rounded,
                    color: NuvoColors.white,
                    size: 44,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No proof is submitted from this screen.',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: NuvoColors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Continue to the race proof form to log real backend progress.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.softBlue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            NuvoPrimaryButton(
              label: 'Submit proof',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: () => context.go('/race/$id/proof'),
            ),
          ],
        ),
      ),
    );
  }
}
