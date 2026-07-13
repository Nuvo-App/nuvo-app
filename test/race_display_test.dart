import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/race_display.dart';

void main() {
  Race makeRace({
    required String status,
    List<RaceParticipant> participants = const [],
    List<RaceFinalStanding> finalStandings = const [],
    int targetValue = 6,
    String activityId = 'push_ups',
    String metric = 'reps',
    String? winnerUserId,
    String? completedAt,
  }) {
    return Race(
      id: 'race-1',
      creatorId: 'user-a',
      title:
          'First to $targetValue ${activityId == 'plank_hold' ? 'Plank Seconds' : 'Pushups'}',
      goalType: 'first_to_goal',
      targetValue: targetValue,
      unit: metric,
      activityId: activityId,
      metric: metric,
      format: 'first_to_goal',
      scoringRule: 'cumulative_sum',
      status: status,
      winnerUserId: winnerUserId,
      completedAt: completedAt,
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      participants: participants,
      finalStandings: finalStandings,
    );
  }

  RaceParticipant participant({
    required String userId,
    required int score,
    required int percent,
    int? rank,
    String joinedAt = '2026-01-01T00:00:00Z',
  }) {
    return RaceParticipant(
      id: 'rp-$userId',
      userId: userId,
      displayName: userId,
      progressValue: score,
      progressPercent: percent,
      rank: rank,
      joinedAt: joinedAt,
    );
  }

  RaceFinalStanding standing({
    required String userId,
    required int rank,
    required int scoreValue,
  }) {
    return RaceFinalStanding(
      userId: userId,
      displayName: userId,
      rank: rank,
      scoreValue: scoreValue,
    );
  }

  group('Progress rendering', () {
    test('caps visual progress but keeps raw over-target score labels', () {
      final race = makeRace(
        status: 'completed',
        participants: [
          participant(userId: 'user-a', score: 7, percent: 100, rank: 1),
        ],
      );
      final me = race.participantFor('user-a');
      expect(raceProgressPercent(race, me), 100);
      expect(raceProgressLabel(race, me), '7 / 6 reps');
      expect(raceIsCompleted(race), isTrue);
    });

    test('target 15: intermediate progress shows correct fraction label', () {
      final race = makeRace(
        status: 'active',
        targetValue: 15,
        participants: [
          participant(userId: 'user-a', score: 10, percent: 67, rank: 1),
        ],
      );
      final me = race.participantFor('user-a');
      expect(raceProgressLabel(race, me), '10 / 15 reps');
      expect(raceProgressPercent(race, me), 66);
    });

    test('target 100: partial completion renders as fraction', () {
      final race = makeRace(
        status: 'active',
        targetValue: 100,
        participants: [
          participant(userId: 'user-a', score: 17, percent: 17, rank: 1),
        ],
      );
      final me = race.participantFor('user-a');
      expect(raceProgressLabel(race, me), '17 / 100 reps');
      expect(raceProgressPercent(race, me), 17);
    });

    test('plank progress label uses seconds not reps', () {
      final race = makeRace(
        status: 'active',
        targetValue: 300,
        activityId: 'plank_hold',
        metric: 'seconds',
        participants: [
          participant(userId: 'user-a', score: 90, percent: 30, rank: 1),
        ],
      );
      final me = race.participantFor('user-a');
      expect(raceProgressLabel(race, me), '90 / 300 seconds');
    });

    test('over-target plank score preserved with visual percent capped', () {
      final race = makeRace(
        status: 'completed',
        targetValue: 60,
        activityId: 'plank_hold',
        metric: 'seconds',
        participants: [
          participant(userId: 'user-a', score: 75, percent: 100, rank: 1),
        ],
      );
      final me = race.participantFor('user-a');
      expect(raceProgressPercent(race, me), 100);
      expect(raceProgressLabel(race, me), '75 / 60 seconds');
    });

    test('no target race: progress label shows just score and metric', () {
      final race = makeRace(
        status: 'active',
        targetValue: 0,
        participants: [
          participant(userId: 'user-a', score: 12, percent: 50, rank: 1),
        ],
      );
      final me = race.participantFor('user-a');
      expect(raceProgressLabel(race, me), '12 reps');
    });

    test('null participant returns default progress label', () {
      final race = makeRace(status: 'active');
      expect(raceProgressLabel(race, null), 'Submit your first proof');
    });
  });

  group('Rank rendering', () {
    test('uses backend ranks before local score sorting', () {
      final race = makeRace(
        status: 'active',
        participants: [
          participant(userId: 'user-a', score: 4, percent: 67, rank: 2),
          participant(userId: 'user-b', score: 5, percent: 83, rank: 1),
          participant(userId: 'user-c', score: 4, percent: 67, rank: 2),
        ],
      );

      expect(rankForUser(race, 'user-c'), 2);
      expect(serverRankedParticipants(race).map((p) => p.userId), [
        'user-b',
        'user-a',
        'user-c',
      ]);
      expect(raceRankLabel(race, 'user-a'), 'Tied #2');
    });

    test(
      'rankForUser prefers finalStandings over participant rank for completed races',
      () {
        final race = makeRace(
          status: 'completed',
          participants: [
            participant(userId: 'user-a', score: 17, percent: 100, rank: 1),
            participant(userId: 'user-b', score: 10, percent: 67, rank: 2),
          ],
          finalStandings: [
            standing(userId: 'user-a', rank: 1, scoreValue: 17),
            standing(userId: 'user-b', rank: 2, scoreValue: 10),
          ],
        );
        expect(rankForUser(race, 'user-a'), 1);
        expect(rankForUser(race, 'user-b'), 2);
      },
    );

    test('raceRankLabel shows Tied prefix for tied participants', () {
      final race = makeRace(
        status: 'active',
        participants: [
          participant(userId: 'user-a', score: 10, percent: 67, rank: 1),
          participant(userId: 'user-b', score: 10, percent: 67, rank: 1),
        ],
      );
      expect(raceRankLabel(race, 'user-a'), 'Tied #1');
    });

    test('single participant at rank 1 has no tied prefix', () {
      final race = makeRace(
        status: 'active',
        participants: [
          participant(userId: 'user-a', score: 10, percent: 67, rank: 1),
          participant(userId: 'user-b', score: 5, percent: 33, rank: 2),
        ],
      );
      expect(raceRankLabel(race, 'user-a'), '#1');
    });
  });

  group('Race completion state', () {
    test('raceIsCompleted is true only for completed status', () {
      expect(raceIsCompleted(makeRace(status: 'completed')), isTrue);
      expect(raceIsCompleted(makeRace(status: 'active')), isFalse);
    });

    test('raceIsActive is true only for active status', () {
      expect(raceIsActive(makeRace(status: 'active')), isTrue);
      expect(raceIsActive(makeRace(status: 'completed')), isFalse);
    });

    test('raceStatusLabel returns human-readable labels', () {
      expect(raceStatusLabel(makeRace(status: 'completed')), 'Finished');
      expect(raceStatusLabel(makeRace(status: 'active')), 'Live');
    });
  });

  group('Submission result parsing', () {
    test('RaceSubmissionResult.fromJson parses all fields correctly', () {
      final result = RaceSubmissionResult.fromJson({
        'verifiedValue': 7,
        'previousScore': 10,
        'newScore': 17,
        'previousRank': 2,
        'newRank': 1,
        'peoplePassed': 1,
        'raceCompleted': true,
        'winnerUserId': 'user-a',
      });
      expect(result.verifiedValue, 7);
      expect(result.newScore, 17);
      expect(result.raceCompleted, isTrue);
      expect(result.winnerUserId, 'user-a');
      expect(result.peoplePassed, 1);
    });

    test(
      'RaceSubmissionResult.fromJson handles idempotent retry (same score)',
      () {
        final result = RaceSubmissionResult.fromJson({
          'verifiedValue': 4,
          'previousScore': 10,
          'newScore': 10,
          'previousRank': 1,
          'newRank': 1,
          'peoplePassed': 0,
          'raceCompleted': false,
          'winnerUserId': null,
        });
        expect(result.newScore, 10);
        expect(result.raceCompleted, isFalse);
      },
    );

    test('RaceFinalStanding.fromJson parses rank and scoreValue', () {
      final s = RaceFinalStanding.fromJson({
        'userId': 'user-a',
        'displayName': 'Alice',
        'rank': 1,
        'scoreValue': 17,
        'completedAt': '2026-01-01T00:05:00Z',
      });
      expect(s.rank, 1);
      expect(s.scoreValue, 17);
      expect(s.displayName, 'Alice');
    });
  });

  group('Legacy race compatibility', () {
    test('Race.fromJson reads goalType as manual for legacy races', () {
      final race = Race.fromJson({
        'id': 'legacy-1',
        'creatorId': 'user-a',
        'title': 'Old manual race',
        'goalType': 'manual',
        'status': 'active',
        'createdAt': '2025-01-01T00:00:00Z',
        'updatedAt': '2025-01-01T00:00:00Z',
      });
      expect(race.goalType, 'manual');
      expect(race.format, 'first_to_goal');
    });

    test('Race.fromJson falls back metric from unit for legacy races', () {
      final race = Race.fromJson({
        'id': 'legacy-2',
        'creatorId': 'user-a',
        'title': 'Push-up race',
        'goalType': 'first_to_goal',
        'targetValue': 50,
        'unit': 'reps',
        'status': 'active',
        'createdAt': '2025-01-01T00:00:00Z',
        'updatedAt': '2025-01-01T00:00:00Z',
      });
      expect(race.metric, 'reps');
    });

    test(
      'Race.fromJson falls back activityId from aiActivityType for legacy races',
      () {
        final race = Race.fromJson({
          'id': 'legacy-3',
          'creatorId': 'user-a',
          'title': 'Push-up race',
          'goalType': 'first_to_goal',
          'aiActivityType': 'push_ups',
          'status': 'active',
          'createdAt': '2025-01-01T00:00:00Z',
          'updatedAt': '2025-01-01T00:00:00Z',
        });
        expect(race.activityId, 'push_ups');
      },
    );
  });
}
