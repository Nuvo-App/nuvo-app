import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

void main() {
  test('shipped flow: intro, sign-in, email, code, player card only', () {
    for (final s in [
      OnboardingStep.introHow,
      OnboardingStep.questions1,
      OnboardingStep.questions2,
      OnboardingStep.levelUp,
      OnboardingStep.firstRaceReady,
      OnboardingStep.arenaTour,
      OnboardingStep.notifyOptIn,
      OnboardingStep.tourProfile,
    ]) {
      expect(kCutSteps, contains(s), reason: s.name);
    }
    for (final s in [
      OnboardingStep.introRace,
      OnboardingStep.signIn,
      OnboardingStep.email,
      OnboardingStep.code,
      OnboardingStep.playerCard,
    ]) {
      expect(kCutSteps, isNot(contains(s)), reason: s.name);
    }
  });

  test(
    'shipped config: the player card is the last step, then it graduates',
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
        OnboardingStep.signIn,
        OnboardingStep.email,
        OnboardingStep.code,
        OnboardingStep.playerCard,
      ]) {
        expect(c.state.step, s);
        expect(c.state.readyToGraduate, isFalse);
        await c.completeStep(s);
      }
      expect(c.state.readyToGraduate, isTrue);
      expect(await c.graduate(), isTrue);
    },
  );
}
