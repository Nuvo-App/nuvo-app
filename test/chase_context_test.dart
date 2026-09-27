import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/chase_context.dart';

Race _race({
  List<RaceParticipant> participants = const [],
  String format = 'first_to_goal',
  String scoreDirection = 'higher',
  String? finishLineAt,
  String? serverTime,
  RaceViewerContext? viewerContext,
  int? targetValue = 100,
}) => Race(
  id: 'r1',
  creatorId: 'riley',
  title: 'Test race',
  goalType: format,
  format: format,
  targetValue: targetValue,
  status: 'active',
  createdAt: '2026-09-20T00:00:00Z',
  updatedAt: '2026-09-20T00:00:00Z',
  participants: participants,
  scoreDirection: scoreDirection,
  finishLineAt: finishLineAt,
  serverTime: serverTime,
  viewerContext: viewerContext,
);

RaceParticipant _p(
  String id,
  int score, {
  int? rank,
  String? name,
}) => RaceParticipant(
  id: 'm_$id',
  userId: id,
  displayName: name ?? id,
  progressValue: score,
  progressPercent: 0,
  rank: rank,
  joinedAt: '2026-09-20T00:00:00Z',
);

void main() {
  group('ChaseContext server-driven context', () {
    test('server viewerContext wins over client computation', () {
      final race = _race(
        participants: [
          _p('riley', 80, rank: 1),
          _p('me', 50, rank: 2),
          _p('maya', 40, rank: 3),
        ],
        viewerContext: const RaceViewerContext(
          raceId: 'r1',
          status: 'active',
          rank: 2,
          leaderUserId: 'riley',
          leaderScore: 80,
          viewerScore: 50,
          gapToLeader: 30,
          gapToNextRank: 30,
        ),
      );
      final ctx = ChaseContext.compute(race, 'me');
      expect(ctx.myRank, 2);
      expect(ctx.leaderGap, 30);
      expect(ctx.leaderName, 'riley');
    });

    test('timeLeft derives from server timeRemainingSeconds', () {
      final race = _race(
        format: 'most_in_window',
        viewerContext: const RaceViewerContext(
          raceId: 'r1',
          status: 'active',
          timeRemainingSeconds: 4 * 3600,
        ),
      );
      final ctx = ChaseContext.compute(race, 'me');
      expect(ctx.timeLeft, '4h');
      expect(ctx.daysLeft, 0);
    });

    test('timeLeft falls back to finishLineAt vs serverTime', () {
      final race = _race(
        format: 'most_in_window',
        finishLineAt: '2026-09-28T00:00:00Z',
        serverTime: '2026-09-24T00:00:00Z',
      );
      final ctx = ChaseContext.compute(race, 'me');
      expect(ctx.timeLeft, '4d');
      expect(ctx.daysLeft, 4);
    });

    test('client fallback still works without viewerContext', () {
      final race = _race(
        participants: [
          _p('riley', 80, rank: 1),
          _p('me', 50, rank: 2),
        ],
      );
      final ctx = ChaseContext.compute(race, 'me');
      expect(ctx.myRank, 2);
      expect(ctx.leaderGap, 30);
    });
  });

  group('ChaseContext lower-is-better direction', () {
    test('zero scores rank last for fastest-time races', () {
      final race = _race(
        format: 'best_attempt',
        scoreDirection: 'lower',
        participants: [
          _p('unplayed', 0),
          _p('slow', 450),
          _p('fast', 382),
        ],
      );
      final ctx = ChaseContext.compute(race, 'fast');
      expect(ctx.myRank, 1);
      final slow = ChaseContext.compute(race, 'slow');
      expect(slow.myRank, 2);
      final unplayed = ChaseContext.compute(race, 'unplayed');
      expect(unplayed.myRank, 3);
    });

    test('gap direction flips for fastest-time races', () {
      final race = _race(
        format: 'best_attempt',
        scoreDirection: 'lower',
        participants: [_p('riley', 382, rank: 1), _p('me', 400, rank: 2)],
      );
      final ctx = ChaseContext.compute(race, 'me');
      expect(ctx.leaderGap, 18); // 18 seconds behind, not -18
    });
  });
}
