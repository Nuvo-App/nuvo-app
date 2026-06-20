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
