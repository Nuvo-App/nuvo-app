import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_progress_presentation.dart';

/// S6 gap 17 — live varied encouragement: copy pools keyed on phase,
/// streak, elapsed time and milestone/new-best beats, rotating without
/// immediate repeats.
void main() {
  group('S6 gap 17 — session encouragement', () {
    test('test_gap17_encouragement_rotates_within_phase', () {
      final e = SessionEncouragement();

      // Same phase across ticks: every line comes from that phase's pool
      // and no two consecutive draws repeat.
      var previous = e.phaseLine(
        MotionProgressPhase.keepGoing,
        elapsedSeconds: 0,
        rotationTick: 0,
      );
      expect(SessionEncouragement.keepGoingPool, contains(previous));
      for (var tick = 1; tick <= SessionEncouragement.keepGoingPool.length * 2;
          tick++) {
        final line = e.phaseLine(
          MotionProgressPhase.keepGoing,
          elapsedSeconds: 0,
          rotationTick: tick,
        );
        expect(SessionEncouragement.keepGoingPool, contains(line));
        expect(line, isNot(previous));
        previous = line;
      }

      // A phase step draws from the new phase's pool immediately.
      expect(
        SessionEncouragement.halfwayPool,
        contains(e.phaseLine(MotionProgressPhase.halfway, rotationTick: 9)),
      );

      // The line is stable inside a tick — rebuilding the HUD doesn't
      // burn through the pool.
      final steady = e.phaseLine(
        MotionProgressPhase.halfway,
        rotationTick: 10,
      );
      expect(
        e.phaseLine(MotionProgressPhase.halfway, rotationTick: 10),
        steady,
      );

      // Elapsed time re-keys the pool: a long keep-going take talks in
      // the late-take voice.
      final lateLine = e.phaseLine(
        MotionProgressPhase.keepGoing,
        elapsedSeconds: SessionEncouragement.lateElapsedSeconds,
        rotationTick: 11,
      );
      expect(SessionEncouragement.keepGoingLatePool, contains(lateLine));

      // Moment flashes draw once per beat from their own pools.
      e.triggerMilestone();
      expect(SessionEncouragement.milestonePool, contains(e.flashLine));
      e.triggerNewBest();
      expect(SessionEncouragement.newBestPool, contains(e.flashLine));
    });

    test('test_gap17_streak_lines_come_from_pool', () {
      final e = SessionEncouragement();

      // Depth picks the band — and every line is a pool line, never a
      // hard-coded one.
      for (var streak = 2; streak <= 4; streak++) {
        expect(
          SessionEncouragement.streakPool,
          contains(e.streakLine(streak)),
        );
      }
      for (var streak = 5; streak <= 9; streak++) {
        expect(
          SessionEncouragement.streakHotPool,
          contains(e.streakLine(streak)),
        );
      }
      for (var streak = 10; streak <= 15; streak++) {
        expect(
          SessionEncouragement.streakOnFirePool,
          contains(e.streakLine(streak)),
        );
      }

      // Within a band, back-to-back reps rotate the line.
      final e2 = SessionEncouragement();
      final seen = <String>{
        e2.streakLine(6),
        e2.streakLine(7),
        e2.streakLine(8),
      };
      expect(seen.length, greaterThan(1));
      expect(
        seen.every(SessionEncouragement.streakHotPool.contains),
        isTrue,
      );
    });
  });
}
