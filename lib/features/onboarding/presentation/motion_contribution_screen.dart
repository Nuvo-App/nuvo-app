import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/v13/v13.dart';
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
  DateTime? _stepOpenedAt;

  @override
  void initState() {
    super.initState();
    _stepOpenedAt = DateTime.now();
    ref
        .read(analyticsProvider)
        .onboardingStepViewed(stepIndex: 1, stepName: 'motion_consent');
  }

  Future<void> _choose(bool consented) async {
    if (_saving) return;
    setState(() => _saving = true);
    final openedAt = _stepOpenedAt;
    ref
        .read(analyticsProvider)
        .onboardingStepCompleted(
          stepIndex: 1,
          stepName: 'motion_consent',
          msOnStep: openedAt == null
              ? null
              : DateTime.now().difference(openedAt).inMilliseconds,
        );
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
      backgroundColor: V13.bg,
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
                          color: i <= 2 ? V13.blue : V13.divider,
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
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NuvoFlipText(
                            'Help make Nuvo better',
                            textAlign: TextAlign.center,
                            style: V13.title.copyWith(
                              fontSize: 32,
                              letterSpacing: -0.9,
                            ),
                            delay: const Duration(milliseconds: 150),
                            duration: const Duration(milliseconds: 1300),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nuvo can save the motion points '
                            'from your movement to improve its '
                            'motion models.',
                            textAlign: TextAlign.center,
                            style: V13.body.copyWith(
                              color: V13.muted,
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ).animate(delay: 400.ms).fadeIn(duration: 280.ms),
                          const SizedBox(height: 24),
                          // Three tiny visual facts — what consenting
                          // actually means, scannable at a glance.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (i, fact) in const [
                                (
                                  icon: Icons.accessibility_new_rounded,
                                  label: 'Motion points only',
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
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child:
                                      Column(
                                            children: [
                                              Container(
                                                width: 46,
                                                height: 46,
                                                decoration: const BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: V13.card,
                                                  border: Border.fromBorderSide(
                                                    BorderSide(
                                                      color: V13.navy,
                                                      width: 2,
                                                    ),
                                                  ),
                                                ),
                                                child: Icon(
                                                  fact.icon,
                                                  color: V13.blue,
                                                  size: 21,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                fact.label,
                                                textAlign: TextAlign.center,
                                                style: V13.caption.copyWith(
                                                  fontSize: 13,
                                                  color: V13.navy,
                                                  fontWeight: FontWeight.w700,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ],
                                          )
                                          .animate(delay: 480.ms + (i * 120).ms)
                                          .fadeIn(duration: 300.ms)
                                          .slideY(begin: .15, duration: 300.ms),
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
              V13Button.primary(
                label: 'Help improve Nuvo',
                icon: Icons.auto_awesome_rounded,
                fullWidth: true,
                loading: _saving,
                onPressed: () => _choose(true),
              ),
              const SizedBox(height: 12),
              V13Button.ghost(
                label: 'Not now',
                fullWidth: true,
                onPressed: _saving ? null : () => _choose(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
