import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/domain/motion_progress_presentation.dart';

void main() {
  group('ContinuationProgress — the display / submit model', () {
    test('target 6, existing 0: session +1 → displayed 1, submit 1', () {
      const c = ContinuationProgress(startingRaceProgress: 0, raceTarget: 6);
      expect(c.sessionTarget, 6);
      expect(c.displayedProgress(0), 0);
      expect(c.displayedProgress(1), 1);
      expect(c.contributionToSubmit(1), 1);
      expect(c.completedAfter(1), isFalse);
    });

    test('target 6, existing 4: opens at 4/6, not 0/2', () {
      const c = ContinuationProgress(startingRaceProgress: 4, raceTarget: 6);
      expect(c.sessionTarget, 2); // verifier only needs 2 more this session
      expect(c.displayedProgress(0), 4); // <- the whole point
      expect(c.displayedProgress(1), 5);
      expect(c.displayedProgress(2), 6);
    });

    test('target 6, existing 4: session +2 completes; backend gets 2, not 6', () {
      const c = ContinuationProgress(startingRaceProgress: 4, raceTarget: 6);
      expect(c.displayedProgress(2), 6);
      expect(c.completedAfter(2), isTrue);
      expect(c.contributionToSubmit(2), 2); // never re-submits the banked 4
    });

    test('overshoot is capped for display but the real contribution stands', () {
      const c = ContinuationProgress(startingRaceProgress: 4, raceTarget: 6);
      expect(c.displayedProgress(5), 6); // clamped
      expect(c.contributionToSubmit(5), 5); // server takes it, then caps score
    });

    test('distance: target 100 m, existing 37 → opens at 37, +8 → 45', () {
      const c = ContinuationProgress(startingRaceProgress: 37, raceTarget: 100);
      expect(c.sessionTarget, 63);
      expect(c.displayedProgress(0), 37);
      expect(c.displayedProgress(8), 45);
      expect(c.contributionToSubmit(8), 8);
      expect(c.completedAfter(8), isFalse);
      expect(c.completedAfter(63), isTrue);
    });

    test('no target (open-ended) still shows a running total', () {
      const c = ContinuationProgress(startingRaceProgress: 12, raceTarget: 0);
      expect(c.displayedProgress(3), 15);
      expect(c.completedAfter(999), isFalse);
    });
  });

  group('reload: the verifier opens at the persisted race progress', () {
    // The verifier machine counts a session toward `sessionTarget`
    // (= remaining). Its `currentValue` is the session contribution; the
    // screen adds `startingRaceProgress` for the primary number.
    test('rep preset: a 3-rep session on a 4/10 race shows 4→7', () {
      const c = ContinuationProgress(startingRaceProgress: 4, raceTarget: 10);
      final v = createMotionValidator(AiMotionActivity.pushUps, c.sessionTarget)
        ..start();
      // simulate the machine having counted 3 this session
      // (currentValue is min(count, sessionTarget))
      expect(c.sessionTarget, 6);
      // displayed progress for session=3:
      expect(c.displayedProgress(3), 7);
      expect(v.currentValue, 0); // fresh session starts at 0 internally
    });
  });
}
