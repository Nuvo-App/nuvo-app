import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/race_detail/domain/race_poll_backoff.dart';
import 'package:nuvo/features/races/data/race_models.dart';

Race _race({String status = 'active', String updatedAt = 't1', int progress = 0}) =>
    Race(
      id: 'r1',
      creatorId: 'u1',
      title: 'T',
      goalType: 'reps',
      status: status,
      createdAt: 't0',
      updatedAt: updatedAt,
      participants: [
        RaceParticipant(
          id: 'p1',
          userId: 'u1',
          displayName: 'A',
          progressValue: progress,
          progressPercent: 0,
          joinedAt: 't0',
        ),
      ],
    );

void main() {
  group('RacePollBackoff', () {
    test('starts at 5s', () {
      expect(RacePollBackoff().current, const Duration(seconds: 5));
    });

    test('moves to 15s after 3 unchanged results, not before', () {
      final b = RacePollBackoff();
      b.recordResult(changed: false);
      b.recordResult(changed: false);
      expect(b.current, const Duration(seconds: 5));
      b.recordResult(changed: false);
      expect(b.current, const Duration(seconds: 15));
      b.recordResult(changed: false);
      expect(b.current, const Duration(seconds: 15));
    });

    test('a change resets to 5s', () {
      final b = RacePollBackoff();
      for (var i = 0; i < 4; i++) {
        b.recordResult(changed: false);
      }
      b.recordResult(changed: true);
      expect(b.current, const Duration(seconds: 5));
    });

    test('a change mid-streak restarts the count', () {
      final b = RacePollBackoff();
      b.recordResult(changed: false);
      b.recordResult(changed: false);
      b.recordResult(changed: true);
      b.recordResult(changed: false);
      b.recordResult(changed: false);
      expect(b.current, const Duration(seconds: 5));
    });

    test('reset returns to 5s', () {
      final b = RacePollBackoff();
      for (var i = 0; i < 3; i++) {
        b.recordResult(changed: false);
      }
      b.reset();
      expect(b.current, const Duration(seconds: 5));
    });
  });

  group('raceSignature', () {
    test('same race gives same signature', () {
      expect(raceSignature(_race()), raceSignature(_race()));
    });
    test('progress, updatedAt and status changes alter it', () {
      final base = raceSignature(_race());
      expect(raceSignature(_race(progress: 3)), isNot(base));
      expect(raceSignature(_race(updatedAt: 't2')), isNot(base));
      expect(raceSignature(_race(status: 'completed')), isNot(base));
    });
  });
}
