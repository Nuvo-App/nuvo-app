import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_step.dart';

/// The onboarding progress bar — honest, but encouraging.
///
/// Every screen the player really passes is one unit of work:
///   5 intro pages + 3 setup stages (sign in, verify, profile) = 8 units.
/// `done` = units already completed when the screen is showing:
///   intro page p (1-based): p - 1      sign-in / create page: 5
///   email: 5      code: 6      player card: 7      finished: 8
/// The bar shows an ease-out of the real ratio:
///   fraction = 1 - (1 - done / 8) ^ 1.5
/// It starts moving faster (so early progress is felt), but it is the SAME
/// monotone curve everywhere — 0 at the start, exactly 1.0 at the end — so it
/// never claims more than the true remaining count allows, and a per-process
/// floor guarantees it never moves backwards (e.g. after Back).
/// The bar is hidden on intro page 1.
abstract final class ObProgress {
  static const int introPages = 5;
  static const int setupStages = 3;
  static const int total = introPages + setupStages;
  static const double easePower = 1.5;

  /// Highest fraction shown so far this run (never goes down).
  static double _floor = 0;

  static void reset() => _floor = 0;

  static double fractionFor(int done) {
    final ratio = (done / total).clamp(0.0, 1.0);
    return 1 - math.pow(1 - ratio, easePower).toDouble();
  }

  /// Monotone: remembers the high-water mark.
  static double shown(int done) {
    _floor = math.max(_floor, fractionFor(done));
    return _floor;
  }

  /// Units completed while [step] is on screen (intro handled by page).
  static int? doneForStep(OnboardingStep step) => switch (step) {
    OnboardingStep.signIn || OnboardingStep.createAccount => introPages,
    OnboardingStep.email => introPages,
    OnboardingStep.code => introPages + 1,
    OnboardingStep.playerCard => introPages + 2,
    _ => null,
  };

  static int doneForIntroPage(int page) => page; // 0-based page == p - 1
}

/// Thin outlined bar, blue fill that springs to its value.
class ObProgressBar extends StatelessWidget {
  const ObProgressBar({super.key, required this.done, this.light = false});

  final int done;

  /// On a colored/dark field: white track instead of the page color.
  final bool light;

  @override
  Widget build(BuildContext context) {
    final value = ObProgress.shown(done);
    final reduce = NuvoMotion.reduceMotionOf(context);
    return Semantics(
      label: 'Setup progress',
      value: '${(value * 100).round()} percent',
      child: Container(
        key: const ValueKey('ob-progress'),
        height: 10,
        decoration: BoxDecoration(
          color: light ? V13.white.withValues(alpha: 0.4) : V13.card,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: value),
            duration: reduce ? Duration.zero : NuvoMotion.springDuration,
            curve: NuvoMotion.spring,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const ColoredBox(color: V13.blue),
            ),
          ),
        ),
      ),
    );
  }
}
