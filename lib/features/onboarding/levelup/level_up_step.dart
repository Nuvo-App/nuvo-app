import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/placeholder_hero.dart';

/// S16 — LEVEL UP, the one full-bleed blue screen. Part F builds the real
/// moment (confetti burst, badge flip, share); the stub fires
/// [OnboardingFlowController.levelUpSeen] once and routes the graduation
/// CTA through the host (Enter the Arena → server write → /arena).
class ObLevelUpStep extends ConsumerStatefulWidget {
  const ObLevelUpStep({super.key});

  @override
  ConsumerState<ObLevelUpStep> createState() => _ObLevelUpStepState();
}

class _ObLevelUpStepState extends ConsumerState<ObLevelUpStep> {
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(onboardingFlowProvider.notifier).levelUpSeen();
    });
  }

  /// Graduation itself is the host's job (it owns the /arena handoff and
  /// the "flow is ready" listen); the stub's CTA re-triggers the same
  /// graduate() write so a failed first attempt retries inline.
  Future<void> _enter() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await ref.read(onboardingFlowProvider.notifier).graduate();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
    // ok → the host's readyToGraduate listen performs context.go('/arena').
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: OnboardingStep.levelUp,
      background: V13.blue,
      titleColor: V13.white,
      subtitleColor: V13.white,
      showTrack: false,
      showRail: false,
      hero: const ObPlaceholderHero(
        step: OnboardingStep.levelUp,
        color: V13.card,
        label: '${ObCopy.levelUpFrom} → ${ObCopy.levelUpTo}',
      ),
      title: ObCopy.levelUpTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${ObCopy.levelUpXpTile} · ${ObCopy.levelUpBadgeTile} · '
            '${ObCopy.levelUpStreakTile}',
            style: V13.bodyStrong.copyWith(color: V13.white),
          ),
          if (_failed) ...[
            const SizedBox(height: V13.gapMd),
            Text(
              ObCopy.genericRetry,
              style: V13.bodyStrong.copyWith(color: V13.coral),
            ),
          ],
        ],
      ),
      ctaLabel: _busy ? '...' : ObCopy.levelUpCta,
      ctaEnabled: !_busy,
      onCta: _enter,
    );
  }
}
