import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/domain/motion_progress_presentation.dart';

void main() {
  group('DistancePresentationPolicy — scale-aware, centralized', () {
    ({int step, bool pace}) p(int m) {
      final x = DistancePresentationPolicy.forTarget(m);
      return (step: x.milestoneStepMetres, pace: x.showsPace);
    }

    test('short sprint (10–25 m): frequent milestones, no pace', () {
      expect(p(10), (step: 5, pace: false));
      expect(p(25), (step: 5, pace: false));
    });

    test('50–100 m: ~10 m milestones', () {
      expect(p(50), (step: 10, pace: false));
      expect(p(100), (step: 10, pace: false));
    });

    test('~200 m band: ~25 m milestones', () {
      expect(p(150), (step: 25, pace: false));
      expect(p(399), (step: 25, pace: false));
    });

    test('mile-scale (>= 400 m): no bursts, pace + intensity', () {
      expect(p(402), (step: 0, pace: true)); // 0.25 mi
      expect(p(1609), (step: 0, pace: true)); // 1 mi
      expect(DistancePresentationPolicy.forTarget(1609).usesMilestoneBursts,
          isFalse);
    });

    test('milestonesCrossed increments once per step, never per metre', () {
      final policy = DistancePresentationPolicy.forTarget(50); // step 10
      expect(policy.milestonesCrossed(0), 0);
      expect(policy.milestonesCrossed(7), 0);
      expect(policy.milestonesCrossed(10), 1);
      expect(policy.milestonesCrossed(19), 1);
      expect(policy.milestonesCrossed(31), 3);
      expect(policy.metresAtMilestone(3), 30);
    });

    test('a mile run crosses zero milestone bursts', () {
      final policy = DistancePresentationPolicy.forTarget(1609);
      expect(policy.milestonesCrossed(800), 0);
    });

    test('the burst count over a whole sprint is small (not per-metre)', () {
      final policy = DistancePresentationPolicy.forTarget(25); // step 5
      // Running the full 25 m produces 5 checkpoints, not 25 "+1"s.
      expect(policy.milestonesCrossed(25), 5);
    });
  });

  group('motionProgressPhase — from real percentage', () {
    int phaseAt(int cur, int tgt) =>
        motionProgressPhase(current: cur, target: tgt).index;
    test('ready → keep going → halfway → almost there → finish', () {
      expect(motionProgressPhase(current: 0, target: 10),
          MotionProgressPhase.ready);
      expect(motionProgressPhase(current: 2, target: 10),
          MotionProgressPhase.keepGoing);
      expect(motionProgressPhase(current: 5, target: 10),
          MotionProgressPhase.halfway);
      expect(motionProgressPhase(current: 9, target: 10),
          MotionProgressPhase.almostThere);
      expect(motionProgressPhase(current: 10, target: 10),
          MotionProgressPhase.finish);
      expect(phaseAt(11, 10), MotionProgressPhase.finish.index);
    });
  });

  group('continuation is a SHARED verifier contract', () {
    // Every preset verifier counts a *session from 0* toward the amount still
    // owed; the screen adds the persisted baseline. A new verifier type gets
    // this for free by using ContinuationProgress + createMotionValidator.
    const someCumulative = [
      AiMotionActivity.pushUps,
      AiMotionActivity.jumpingJacks,
      AiMotionActivity.squats,
      AiMotionActivity.lunges,
      AiMotionActivity.runningInPlace,
      AiMotionActivity.treadmillRunning,
      AiMotionActivity.highKnees,
    ];

    for (final activity in someCumulative) {
      test('$activity: session opens at 0 and never exceeds sessionTarget', () {
        const c = ContinuationProgress(startingRaceProgress: 4, raceTarget: 10);
        final v = createMotionValidator(activity, c.sessionTarget)..start();
        expect(v.currentValue, 0, reason: 'a fresh session starts at zero');
        // Feed a burst of frames; whatever it counts, the machine caps at
        // its own session target and the displayed number is baseline + that.
        for (var i = 0; i < 400; i++) {
          v.update(_blankFrame(i));
        }
        expect(v.currentValue, lessThanOrEqualTo(c.sessionTarget));
        expect(c.displayedProgress(v.currentValue),
            inInclusiveRange(4, c.raceTarget));
        expect(c.contributionToSubmit(v.currentValue), v.currentValue);
      });
    }

    test('finish fires on the DISPLAYED total, backend gets only the session',
        () {
      const c = ContinuationProgress(startingRaceProgress: 4, raceTarget: 6);
      expect(c.completedAfter(2), isTrue); // 4 + 2 = 6
      expect(c.contributionToSubmit(2), 2); // not 6
    });
  });
}

NuvoPoseFrame _blankFrame(int i) => NuvoPoseFrame(
      points: const {},
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt: DateTime.fromMillisecondsSinceEpoch(i * 33),
    );
