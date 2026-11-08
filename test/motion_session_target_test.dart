import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_session_target.dart';

void main() {
  group('motionSessionTarget', () {
    test('most total never caps the count (the 5-jumping-jack bug)', () {
      final t = motionSessionTarget(
        format: 'most_in_window',
        isCustom: false,
        raceTarget: null,
        alreadyDone: 12,
        defaultTarget: 5,
      );
      expect(t, kOpenEndedSessionTarget);
      // A validator clamps currentValue to the target: 40 reps stay 40.
      expect(40.clamp(0, t), 40);
    });

    test('timed and best single are open-ended too', () {
      for (final f in ['timed_attempt', 'best_attempt']) {
        expect(
          motionSessionTarget(
            format: f,
            isCustom: false,
            raceTarget: 10,
            alreadyDone: 0,
            defaultTarget: 5,
          ),
          kOpenEndedSessionTarget,
        );
      }
    });

    test('custom movement in a non-first-to race is not stuck at 1', () {
      expect(
        motionSessionTarget(
          format: 'most_in_window',
          isCustom: true,
          raceTarget: null,
          alreadyDone: 0,
          defaultTarget: null,
        ),
        kOpenEndedSessionTarget,
      );
    });

    test('first to keeps its real remaining target', () {
      expect(
        motionSessionTarget(
          format: 'first_to_goal',
          isCustom: false,
          raceTarget: 50,
          alreadyDone: 32,
          defaultTarget: 10,
        ),
        18,
      );
      // Past the goal still needs at least 1.
      expect(
        motionSessionTarget(
          format: 'first_to_goal',
          isCustom: true,
          raceTarget: 20,
          alreadyDone: 25,
          defaultTarget: null,
        ),
        1,
      );
      // No stored goal → the movement default (custom: 1), as before.
      expect(
        motionSessionTarget(
          format: 'first_to_goal',
          isCustom: false,
          raceTarget: null,
          alreadyDone: 0,
          defaultTarget: 10,
        ),
        10,
      );
    });
  });
}
