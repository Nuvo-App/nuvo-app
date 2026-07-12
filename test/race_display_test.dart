import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/race_display.dart';

void main() {
  Race raceWithParticipants({
    required String status,
    List<RaceParticipant> participants = const [],
    int targetValue = 6,
  }) {
    return Race(
      id: 'race-1',
      creatorId: 'user-a',
      title: 'First to $targetValue Pushups',
      goalType: 'first_to_goal',
      targetValue: targetValue,
      unit: 'reps',
      activityId: 'push_ups',
      metric: 'reps',
      status: status,
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      participants: participants,
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

  test('caps visual progress but keeps raw over-target score labels', () {
    final race = raceWithParticipants(
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

  test('uses backend ranks before local score sorting', () {
    final race = raceWithParticipants(
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
}
