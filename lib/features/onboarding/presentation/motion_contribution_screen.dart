import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_flip_text.dart';
import '../../auth/presentation/auth_controller.dart';

/// "Help make Nuvo better" — the motion-contribution choice presented during
/// onboarding. Two real, equal-prominence choices; declining loses nothing.
/// This is consent for motion-POINT data retention, NOT camera permission —
/// camera is still asked later at first AI Motion Proof use.
class MotionContributionScreen extends ConsumerStatefulWidget {
  const MotionContributionScreen({super.key});

  @override
  ConsumerState<MotionContributionScreen> createState() =>
      _MotionContributionScreenState();
}

class _MotionContributionScreenState
    extends ConsumerState<MotionContributionScreen> {
  bool _saving = false;

  Future<void> _choose(bool consented) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .setMotionConsent(consented: consented);
      if (mounted) context.go('/onboarding/nuvo');
    } catch (_) {
      // A consent write failing must not trap onboarding — the choice can be
      // changed later in Settings → Privacy & Data.
      if (mounted) context.go('/onboarding/nuvo');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: i <= 2 ? NuvoColors.blue : NuvoColors.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    if (i < 2) const SizedBox(width: 4),
                  ],
                ],
              ),
              const Spacer(),
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NuvoColors.panel,
                    border: Border.all(color: NuvoColors.navy, width: 2),
                  ),
                  child: const Icon(
                    Icons.motion_photos_on_rounded,
                    color: NuvoColors.blue,
                    size: 34,
                  ),
                ).animate().fadeIn(duration: 320.ms).scale(
                      begin: const Offset(0.85, 0.85),
                      duration: 420.ms,
                      curve: Curves.easeOutBack,
                    ),
              ),
              const SizedBox(height: 30),
              NuvoFlipText(
                'Help make Nuvo better',
                style: AppTextStyles.headlineLarge.copyWith(
                  fontSize: 32,
                  letterSpacing: -0.9,
                  color: NuvoColors.navy,
                ),
                delay: const Duration(milliseconds: 150),
                duration: const Duration(milliseconds: 1300),
              ),
              const SizedBox(height: 16),
              Text(
                'Help Nuvo learn from movement.',
                style: AppTextStyles.titleMedium.copyWith(
                  color: NuvoColors.navy,
                  height: 1.4,
                ),
              ).animate(delay: 400.ms).fadeIn(duration: 280.ms),
              const SizedBox(height: 12),
              Text(
                'When you use AI Motion Proof, Nuvo can save the motion '
                'points created from your movement to improve its '
                'motion models.',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: NuvoColors.muted,
                  height: 1.45,
                ),
              ).animate(delay: 480.ms).fadeIn(duration: 280.ms),
              const SizedBox(height: 14),
              Text(
                'Camera video and audio are never uploaded. You can change '
                'this anytime in Settings.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.muted,
                  height: 1.45,
                ),
              ).animate(delay: 560.ms).fadeIn(duration: 280.ms),
              const Spacer(flex: 2),
              NuvoPrimaryButton(
                label: 'Help improve Nuvo',
                icon: Icons.auto_awesome_rounded,
                expand: true,
                loading: _saving,
                onPressed: () => _choose(true),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _saving ? null : () => _choose(false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: NuvoColors.navy,
                  ),
                  child: Text(
                    'Not now',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
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
