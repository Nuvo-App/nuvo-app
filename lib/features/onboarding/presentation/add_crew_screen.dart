import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';

class AddCrewScreen extends StatelessWidget {
  const AddCrewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NuvoPrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                onPressed: () => context.go('/onboarding/first-race'),
              ),
              const SizedBox(height: 10),
              NuvoOutlineButton(
                label: 'Skip for now',
                expand: true,
                onPressed: () => context.go('/onboarding/first-race'),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++) ...[
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: i <= 3
                                    ? NuvoColors.blue
                                    : NuvoColors.border,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          if (i < 4) const SizedBox(width: 4),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Pull in your crew',
                      style: AppTextStyles.headlineLarge.copyWith(
                        fontSize: 32,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Invite friends from the Crew tab after signing in.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 18,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: NuvoColors.icyBlue,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.group_add_rounded,
                              color: NuvoColors.blue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Your crew is waiting at the start line.',
                            style: AppTextStyles.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap Skip for now and find people later.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: NuvoColors.muted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
                .animate()
                .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                .slideY(
                  begin: 0.04,
                  end: 0,
                  duration: 320.ms,
                  curve: Curves.easeOutCubic,
                ),
      ),
    );
  }
}
