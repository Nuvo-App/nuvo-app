import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

void main() {
  test('shipped flow cuts every placeholder tour step and keeps the rest', () {
    expect(kCutSteps, contains(OnboardingStep.arenaTour));
    expect(kCutSteps, contains(OnboardingStep.notifyOptIn));
    expect(kCutSteps, contains(OnboardingStep.tourProfile));
    expect(kCutSteps, isNot(contains(OnboardingStep.levelUp)));
    expect(kCutSteps, contains(OnboardingStep.firstRaceReady));
  });

  test(
    'shipped config: Q2 is followed directly by Level Up, then graduates',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final c = OnboardingFlowController(
        store: OnboardingV2Store.memory(),
        analytics: FakeAnalyticsService(),
        onGraduate: () async {},
        cutSteps: kCutSteps,
      );
      await c.restore();
      for (final s in [
        OnboardingStep.introRace,
        OnboardingStep.introHow,
        OnboardingStep.signIn,
        OnboardingStep.email,
        OnboardingStep.code,
        OnboardingStep.playerCard,
        OnboardingStep.questions1,
        OnboardingStep.questions2,
      ]) {
        expect(c.state.step, s);
        await c.completeStep(s);
      }
      expect(c.state.step, OnboardingStep.levelUp);
      expect(c.state.readyToGraduate, isFalse);
      expect(await c.graduate(), isTrue);
      await c.completeStep(OnboardingStep.levelUp);
      expect(c.state.readyToGraduate, isTrue);
    },
  );
}
