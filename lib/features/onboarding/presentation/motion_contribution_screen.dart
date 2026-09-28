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
              const SizedBox(height: 20),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              NuvoFlipText(
                                'Help make Nuvo better',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.headlineLarge
                                    .copyWith(
                                      fontSize: 32,
                                      letterSpacing: -0.9,
                                      color: NuvoColors.navy,
                                    ),
                                delay: const Duration(milliseconds: 150),
                                duration: const Duration(
                                  milliseconds: 1300,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Nuvo can save the motion points '
                                'from your movement to improve its '
                                'motion models.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: NuvoColors.muted,
                                  height: 1.45,
                                ),
                              ).animate(delay: 400.ms).fadeIn(
                                    duration: 280.ms,
                                  ),
                              const SizedBox(height: 24),
                              // Three tiny visual facts — what consenting
                              // actually means, scannable at a glance.
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  for (final (i, fact) in const [
                                    (
                                      icon: Icons
                                          .accessibility_new_rounded,
                                      label:
                                          'Motion points only',
                                    ),
                                    (
                                      icon: Icons.videocam_off_rounded,
                                      label: 'No video or audio',
                                    ),
                                    (
                                      icon: Icons.tune_rounded,
                                      label: 'Your choice',
                                    ),
                                  ].indexed) ...[
                                    if (i > 0)
                                      const SizedBox(width: 8),
                                    Expanded(
                                      child:
                                          Column(
                                                children: [
                                                  Container(
                                                    width: 46,
                                                    height: 46,
                                                    decoration:
                                                        BoxDecoration(
                                                          shape: BoxShape
                                                              .circle,
                                                          color:
                                                              NuvoColors
                                                                  .panel,
                                                          border:
                                                              Border.all(
                                                                color:
                                                                    NuvoColors
                                                                        .navy,
                                                                width: 1.6,
                                                              ),
                                                        ),
                                                    child: Icon(
                                                      fact.icon,
                                                      color:
                                                          NuvoColors
                                                              .blue,
                                                      size: 21,
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    height: 8,
                                                  ),
                                                  Text(
                                                    fact.label,
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: AppTextStyles
                                                        .bodySmall
                                                        .copyWith(
                                                          color:
                                                              NuvoColors
                                                                  .navy,
                                                          fontWeight:
                                                              FontWeight
                                                                  .w700,
                                                          height: 1.25,
                                                        ),
                                                  ),
                                                ],
                                              )
                                              .animate(
                                                delay: 480.ms +
                                                    (i * 120).ms,
                                              )
                                              .fadeIn(
                                                duration: 300.ms,
                                              )
                                              .slideY(
                                                begin: .15,
                                                duration: 300.ms,
                                              ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 12),
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
