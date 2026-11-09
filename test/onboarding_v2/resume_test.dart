// Resume-after-kill: the persisted record must resume at the earliest owed
// step and never double-award XP — exercised at EVERY step boundary.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/flow/xp_table.dart';

void main() {
  // completeStep fires a haptic — the binding makes it a silent no-op.
  TestWidgetsFlutterBinding.ensureInitialized();
  _group();
}

OnboardingFlowController _controller(OnboardingV2Store store) =>
    OnboardingFlowController(
      store: store,
      analytics: FakeAnalyticsService(),
      onGraduate: () async {},
    );

/// Drives [c] through [count] steps using each step's real completion seam.
Future<void> _walk(OnboardingFlowController c, int count) async {
  for (var i = 0; i < count; i++) {
    final step = OnboardingStep.values[i];
    switch (step) {
      case OnboardingStep.arenaTour:
        c.proofStarted();
        await c.proofCompleted(cameraFallback: false);
      case OnboardingStep.notifyOptIn:
        await c.setNotifyOutcome('accepted');
        await c.completeStep(step);
      default:
        await c.completeStep(step);
    }
  }
}

void _group() {
  group('kill + relaunch resume', () {
    // One iteration per step boundary — after completing steps 0..k the
    // relaunched flow must owe step k+1 and refuse to re-award step k.
    for (var k = 0; k < OnboardingStep.values.length; k++) {
      final done = OnboardingStep.values[k];
      test(
        'after ${done.name} resumes at the next owed step, no double XP',
        () async {
          // ── First process lifetime ───────────────────────────────────
          final store1 = OnboardingV2Store.memory();
          final c1 = _controller(store1);
          await c1.restore();
          await _walk(c1, k + 1);
          final xpBeforeKill = store1.totalXp;

          // ── Kill: only the serialized record survives ────────────────
          final snapshot = store1.toJson();
          final store2 = OnboardingV2Store.fromSnapshot(snapshot);
          final c2 = _controller(store2);
          await c2.restore();

          final next = done.next;
          expect(
            c2.state.step,
            next ?? OnboardingStep.levelUp,
            reason: 'resume target after ${done.name}',
          );
          expect(store2.totalXp, xpBeforeKill);

          // ── The completed step cannot re-award ───────────────────────
          final reawarded = await c2.completeStep(done);
          expect(reawarded, 0);
          expect(store2.totalXp, xpBeforeKill);
        },
      );
    }

    test('answers, email and fallback flag survive the relaunch', () async {
      final store1 = OnboardingV2Store.memory();
      final c1 = _controller(store1);
      await c1.restore();
      await c1.setAnswer(1, 'Running');
      await c1.setAnswer(2, 'Solo first');
      await c1.setEmail('runner@example.com');
      await c1.setCameraFallback(true);
      await c1.setNotifyOutcome('declined');

      final store2 = OnboardingV2Store.fromSnapshot(store1.toJson());
      final c2 = _controller(store2);
      await c2.restore();
      expect(c2.state.answerQ1, 'Running');
      expect(c2.state.answerQ2, 'Solo first');
      expect(c2.state.email, 'runner@example.com');
      expect(c2.state.cameraFallback, isTrue);
      expect(c2.state.notifyOutcome, 'declined');
      // The fallback flag really does steer the proof award.
      expect(
        OnboardingXp.xpFor(
          OnboardingStep.arenaTour,
          cameraFallback: c2.state.cameraFallback,
        ),
        10,
      );
    });

    test('a fully-walked record restores already-graduable', () async {
      final store1 = OnboardingV2Store.memory();
      final c1 = _controller(store1);
      await c1.restore();
      await _walk(c1, OnboardingStep.values.length); // incl. levelUp

      final store2 = OnboardingV2Store.fromSnapshot(store1.toJson());
      final c2 = _controller(store2);
      await c2.restore();
      expect(c2.state.allStepsComplete, isTrue);
      expect(c2.state.readyToGraduate, isTrue);
      expect(c2.state.totalXp, 100);
    });

    test('a different account signing in wipes the stored progress', () async {
      final store1 = OnboardingV2Store.memory();
      final c1 = _controller(store1);
      await c1.restore();
      await _walk(c1, 7); // through code (+10 XP recorded)
      await c1.attachAccount('first@example.com');

      // Same account → no-op.
      expect(await store1.attachAccount('first@example.com'), isFalse);
      expect(store1.totalXp, 10);

      // Different account → wiped + re-keyed.
      expect(await store1.attachAccount('second@example.com'), isTrue);
      expect(store1.totalXp, 0);
      expect(store1.completedSteps, isEmpty);
    });

    test('a step completed pre-kill stays completed post-kill', () async {
      final store1 = OnboardingV2Store.memory();
      final c1 = _controller(store1);
      await c1.restore();
      await c1.completeStep(OnboardingStep.splash);
      await c1.completeStep(OnboardingStep.introRace);

      final store2 = OnboardingV2Store.fromSnapshot(store1.toJson());
      final c2 = _controller(store2);
      await c2.restore();
      expect(c2.state.step, OnboardingStep.introCamera);
      // And completing the resumed step continues forward, not backward.
      await c2.completeStep(OnboardingStep.introCamera);
      expect(c2.state.step, OnboardingStep.introBoard);
    });
  });
}
