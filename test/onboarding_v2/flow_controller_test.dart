// OnboardingFlowController — the S0–S16 step machine: linear advance,
// skip groups, back-navigation, conditional awards, graduation.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

void main() {
  // Haptics (completeStep/levelUpSeen) hit platform channels — the binding
  // makes them silent no-ops instead of throwing.
  TestWidgetsFlutterBinding.ensureInitialized();
  _group();
}

OnboardingFlowController _controller({
  OnboardingV2Store? store,
  FakeAnalyticsService? analytics,
  Future<void> Function()? onGraduate,
}) => OnboardingFlowController(
  store: store ?? OnboardingV2Store.memory(),
  analytics: analytics ?? FakeAnalyticsService(),
  onGraduate: onGraduate ?? () async {},
);

/// Completes [step] the way its real screen will (proof + notify get
/// their dedicated seams).
Future<int> _act(OnboardingFlowController c, OnboardingStep step) {
  switch (step) {
    case OnboardingStep.arenaTour:
      c.proofStarted();
      return c.proofCompleted(cameraFallback: false);
    case OnboardingStep.notifyOptIn:
      return c.setNotifyOutcome('accepted').then((_) => c.completeStep(step));
    default:
      return c.completeStep(step);
  }
}

void _group() {
  group('OnboardingFlowController', () {
    test(
      'restores onto the first intro for a fresh store (splash is retired)',
      () async {
        final c = _controller();
        await c.restore();
        expect(c.state.restored, isTrue);
        expect(c.state.step, OnboardingStep.introRace);
        expect(c.state.completed, contains(OnboardingStep.splash));
        expect(c.state.totalXp, 0);
      },
    );

    test('walking the whole flow lands on levelUp with 100 XP', () async {
      final c = _controller();
      await c.restore();
      var expected = 0;
      for (final step in OnboardingStep.values) {
        if (step == OnboardingStep.splash) continue;
        if (step == OnboardingStep.levelUp) break;
        expect(c.state.step, step, reason: 'expected ${step.name}');
        expected +=
            {
              OnboardingStep.code: 10,
              OnboardingStep.playerCard: 15,
              OnboardingStep.questions2: 10,
              OnboardingStep.firstRaceReady: 5,
              OnboardingStep.arenaTour: 30,
              OnboardingStep.notifyOptIn: 5,
              OnboardingStep.tourCompete: 10,
              OnboardingStep.tourCrew: 10,
              OnboardingStep.tourProfile: 5,
            }[step] ??
            0;
        await _act(c, step);
        expect(c.state.totalXp, expected, reason: 'after ${step.name}');
      }
      expect(c.state.step, OnboardingStep.levelUp);
      expect(c.state.totalXp, 100);
      expect(c.state.readyToGraduate, isFalse); // levelUp still owed
    });

    test(
      'graduate() runs the server write once and resolves the flow',
      () async {
        var writes = 0;
        final c = _controller(onGraduate: () async => writes++);
        await c.restore();
        for (final step in OnboardingStep.values) {
          if (step == OnboardingStep.splash) continue;
          if (step == OnboardingStep.levelUp) break;
          await _act(c, step);
        }
        expect(await c.graduate(), isTrue);
        expect(writes, 1);
        expect(c.state.allStepsComplete, isTrue);
        expect(c.state.readyToGraduate, isTrue);
      },
    );

    test(
      'graduate() failure never blocks: completes locally, marks pending',
      () async {
        final c = _controller(onGraduate: () async => throw StateError('x'));
        await c.restore();
        for (final step in OnboardingStep.values) {
          if (step == OnboardingStep.splash) continue;
          if (step == OnboardingStep.levelUp) break;
          await _act(c, step);
        }
        // A failed server write still lets the player into Arena — the device
        // records a pending graduation and retries in the background.
        expect(await c.graduate(), isTrue);
        expect(c.state.allStepsComplete, isTrue);
      },
    );

    test('skipIntros compresses S1–S2 onto signIn', () async {
      final c = _controller();
      await c.restore();
      expect(c.state.step, OnboardingStep.introRace);
      await c.skipIntros();
      expect(c.state.step, OnboardingStep.signIn);
      expect(
        c.state.completed,
        containsAll([OnboardingStep.introRace, OnboardingStep.introHow]),
      );
    });

    test(
      'skipQuestions still pays the +10 and lands on firstRaceReady',
      () async {
        final c = _controller();
        await c.restore();
        for (final s in OnboardingStep.values.take(7)) {
          await _act(c, s);
        }
        expect(c.state.step, OnboardingStep.questions1);
        await c.skipQuestions();
        expect(c.state.step, OnboardingStep.firstRaceReady);
        expect(c.state.totalXp, 25 + 10); // code+playerCard + questions
      },
    );

    test('skipTour defers level-up but leaves the flow graduatable', () async {
      final c = _controller();
      await c.restore();
      for (final s in OnboardingStep.values.take(12)) {
        await _act(c, s);
      }
      expect(c.state.step, OnboardingStep.tourCompete);
      await c.skipTour();
      expect(c.state.tourSkipped, isTrue);
      expect(c.state.earliestOwed, OnboardingStep.levelUp);
      expect(c.state.readyToGraduate, isTrue);
      expect(c.state.allStepsComplete, isFalse);
    });

    test('goBack revisits a completed step without un-earning it', () async {
      final c = _controller();
      await c.restore();
      for (final s in OnboardingStep.values.take(6)) {
        await _act(c, s);
      }
      expect(c.state.step, OnboardingStep.playerCard);
      c.goBack();
      expect(c.state.step, OnboardingStep.code);
      expect(c.state.completed, contains(OnboardingStep.code));
      // Re-completing the revisited step re-advances, awards nothing twice.
      final awarded = await c.completeStep(OnboardingStep.code);
      expect(awarded, 0);
      expect(c.state.step, OnboardingStep.playerCard);
    });

    test('camera fallback pays the reduced proof award', () async {
      final c = _controller();
      await c.restore();
      for (final s in OnboardingStep.values.take(10)) {
        await _act(c, s);
      }
      expect(c.state.step, OnboardingStep.arenaTour);
      c.proofStarted();
      final awarded = await c.proofCompleted(cameraFallback: true);
      expect(awarded, 10);
      expect(c.state.cameraFallback, isTrue);
    });

    test('declined notification pays nothing', () async {
      final c = _controller();
      await c.restore();
      for (final s in OnboardingStep.values.take(11)) {
        await _act(c, s);
      }
      expect(c.state.step, OnboardingStep.notifyOptIn);
      await c.setNotifyOutcome('declined');
      final awarded = await c.completeStep(OnboardingStep.notifyOptIn);
      expect(awarded, 0);
    });

    test('analytics fire viewed/completed in order', () async {
      final analytics = FakeAnalyticsService();
      final c = _controller(analytics: analytics);
      await c.restore();
      await c.completeStep(OnboardingStep.introRace);
      final names = analytics.events.map((e) => e.event).toList();
      expect(names, [
        'ob_step_viewed', // introRace on restore (no splash event)
        'ob_step_completed', // introRace
        'ob_step_viewed', // introHow
      ]);
      expect(analytics.events[1].properties['step_name'], 'introRace');
      expect(
        analytics.events[2].properties['step_index'],
        OnboardingStep.introHow.index,
      );
    });
  });
}
