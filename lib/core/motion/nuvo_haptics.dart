import 'package:flutter/services.dart';

import '../v13/motion.dart';

/// Onboarding-v2 haptic vocabulary — every call is gated on the persisted
/// Settings haptics toggle ([v13HapticsEnabled], the same store
/// `V13Haptics` reads, so one Settings switch governs both).
///
/// Spec: selectionClick for chips/dots/XP ticks; lightImpact on every press;
/// mediumImpact on step complete / Track advance; heavyImpact once at
/// level-up; the success pattern (light → 70 ms → medium → 70 ms → heavy)
/// for level-up and email verified.
abstract final class NuvoHaptics {
  /// Chips, page dots, XP ticks.
  static void select() => V13Haptics.select();

  /// Every physical press.
  static void light() => V13Haptics.light();

  /// Step completed / Track advance.
  static void medium() => V13Haptics.confirm();

  /// Level-up — fired once, never for ordinary presses.
  static void heavy() {
    if (v13HapticsEnabled) HapticFeedback.heavyImpact();
  }

  /// The two-beat confirmation: light, 70 ms, medium, 70 ms, heavy.
  /// Level-up and email verified only.
  static Future<void> success() async {
    if (!v13HapticsEnabled) return;
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    if (!v13HapticsEnabled) return;
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    if (!v13HapticsEnabled) return;
    HapticFeedback.heavyImpact();
  }
}
