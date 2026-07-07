import 'package:flutter/material.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';

// Web placeholder for AiMotionProofScreen.
// Camera and MLKit are mobile-only; this screen is shown on web instead.
class AiMotionProofScreen extends StatelessWidget {
  const AiMotionProofScreen({super.key, required this.raceId});

  final String raceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NuvoBackNavRow(
                onBack: () => safePopOrGo(context, '/race/$raceId/proof'),
              ),
              const Spacer(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: NuvoColors.icyBlue,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: NuvoColors.navy, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.phone_iphone_rounded,
                        color: NuvoColors.navy,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Camera verification runs\non the mobile app',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: NuvoColors.navy,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Use the Nuvo mobile app to verify this movement with the camera.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              NuvoPrimaryButton(
                label: 'Back to proof',
                icon: Icons.arrow_back_rounded,
                expand: true,
                onPressed: () => safePopOrGo(context, '/race/$raceId/proof'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
