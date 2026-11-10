// Page-skipping guards: double taps and early taps can never advance twice.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

OnboardingFlowController _c({Duration lock = Duration.zero}) =>
    OnboardingFlowController(
      store: OnboardingV2Store.memory(),
      analytics: FakeAnalyticsService(),
      onGraduate: () async {},
      cutSteps: kCutSteps,
      inputLock: lock,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('double tap on the current step advances exactly one step', () async {
    final c = _c();
    await c.restore();
    await Future.wait([
      c.completeStep(OnboardingStep.introRace),
      c.completeStep(OnboardingStep.introRace),
    ]);
    expect(c.state.step, OnboardingStep.introHow);
  });

  test('a tap during the 600ms lock cannot skip the next page', () async {
    final c = _c(lock: const Duration(milliseconds: 600));
    await c.restore();
    // Arrived on introRace just now: an immediate tap is ignored...
    await c.completeStep(OnboardingStep.introRace);
    expect(c.state.step, OnboardingStep.introRace);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    // ...a real tap works, and an immediate second one cannot skip.
    await c.completeStep(OnboardingStep.introRace);
    expect(c.state.step, OnboardingStep.introHow);
    await c.completeStep(OnboardingStep.introHow);
    expect(c.state.step, OnboardingStep.introHow);
  });

  test('late callback for an earlier step never advances the flow', () async {
    final c = _c();
    await c.restore();
    await c.completeStep(OnboardingStep.introRace);
    await c.completeStep(OnboardingStep.introRace); // stale
    expect(c.state.step, OnboardingStep.introHow);
  });

  test('going back then Next advances one step, not two', () async {
    final c = _c();
    await c.restore();
    await c.completeStep(OnboardingStep.introRace);
    await c.completeStep(OnboardingStep.introHow);
    expect(c.state.step, OnboardingStep.signIn);
    c.goBack();
    expect(c.state.step, OnboardingStep.introHow);
    await c.completeStep(OnboardingStep.introHow);
    expect(c.state.step, OnboardingStep.signIn);
  });

  test('full shipped flow visits every screen once, in order', () async {
    final c = _c();
    await c.restore();
    final seen = <OnboardingStep>[];
    while (!c.state.readyToGraduate) {
      final s = c.state.step;
      seen.add(s);
      await c.completeStep(s);
      await c.completeStep(s); // double tap on every screen
    }
    expect(seen, [
      OnboardingStep.introRace,
      OnboardingStep.introHow,
      OnboardingStep.signIn,
      OnboardingStep.email,
      OnboardingStep.code,
      OnboardingStep.playerCard,
      OnboardingStep.questions1,
      OnboardingStep.questions2,
      OnboardingStep.levelUp,
    ]);
  });
}
