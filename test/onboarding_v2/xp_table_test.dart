// XP table contract — the spec's economy pinned exactly.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/flow/xp_table.dart';

void main() {
  group('OnboardingXp', () {
    test('the full camera path sums to exactly 100', () {
      expect(OnboardingXp.sum(), OnboardingXp.total);
      expect(OnboardingXp.total, 100);
    });

    test('the camera-fallback path sums to 80 (30 → 10 proof)', () {
      expect(
        OnboardingXp.sum(cameraFallback: true),
        OnboardingXp.totalCameraFallback,
      );
      expect(OnboardingXp.totalCameraFallback, 80);
    });

    test('declining notifications loses only the +5', () {
      expect(OnboardingXp.sum(notifyAccepted: false), 95);
    });

    test('per-step awards match the spec values', () {
      expect(OnboardingXp.xpFor(OnboardingStep.code), 10);
      expect(OnboardingXp.xpFor(OnboardingStep.playerCard), 15);
      expect(OnboardingXp.xpFor(OnboardingStep.questions2), 10);
      expect(OnboardingXp.xpFor(OnboardingStep.firstRaceReady), 5);
      expect(OnboardingXp.xpFor(OnboardingStep.arenaTour), 30);
      expect(
        OnboardingXp.xpFor(OnboardingStep.arenaTour, cameraFallback: true),
        10,
      );
      expect(
        OnboardingXp.xpFor(OnboardingStep.notifyOptIn, notifyAccepted: true),
        5,
      );
      expect(OnboardingXp.xpFor(OnboardingStep.notifyOptIn), 0);
      expect(OnboardingXp.xpFor(OnboardingStep.tourCompete), 10);
      expect(OnboardingXp.xpFor(OnboardingStep.tourCrew), 10);
      expect(OnboardingXp.xpFor(OnboardingStep.tourProfile), 5);
    });

    test('steps with no award return 0', () {
      for (final step in [
        OnboardingStep.splash,
        OnboardingStep.introRace,
        OnboardingStep.introHow,
        OnboardingStep.signIn,
        OnboardingStep.email,
        OnboardingStep.questions1,
        OnboardingStep.levelUp,
      ]) {
        expect(OnboardingXp.xpFor(step), 0, reason: step.name);
      }
    });
  });
}
