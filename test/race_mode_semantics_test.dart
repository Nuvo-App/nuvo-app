import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';
import 'package:nuvo/features/races/domain/race_mode_semantics.dart';

void main() {
  RaceParticipant participant({
    required String userId,
    required int score,
    int? rank,
  }) {
    return RaceParticipant(
      id: 'rp-$userId',
      userId: userId,
      displayName: userId,
      progressValue: score,
      progressPercent: score,
      rank: rank,
      joinedAt: '2026-01-01T00:00:00Z',
    );
  }

  Race makeRace({
    String format = 'first_to_goal',
    String scoringRule = 'cumulative_sum',
    String scoreDirection = 'higher',
    String status = 'active',
    int? targetValue,
    String? finishLineAt,
    int? attemptDurationSeconds,
    List<RaceParticipant> participants = const [],
    RaceViewerContext? viewerContext,
  }) {
    return Race(
      id: 'race-1',
      creatorId: 'user-a',
      title: 'Test race',
      goalType: format,
      targetValue: targetValue,
      unit: 'reps',
      activityId: 'push_ups',
      metric: 'reps',
      format: format,
      scoringRule: scoringRule,
      scoreDirection: scoreDirection,
      status: status,
      finishLineAt: finishLineAt,
      attemptDurationSeconds: attemptDurationSeconds,
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      participants: participants,
      viewerContext: viewerContext,
    );
  }

  group('RaceFormat semantics', () {
    test('only first-to-goal uses a score target', () {
      expect(RaceFormat.firstToGoal.usesScoreTarget, isTrue);
      expect(RaceFormat.bestAttempt.usesScoreTarget, isFalse);
      expect(RaceFormat.mostInWindow.usesScoreTarget, isFalse);
      expect(RaceFormat.timedAttempt.usesScoreTarget, isFalse);
    });

    test('cumulative vs attempt-based mirrors the Worker', () {
      expect(RaceFormat.firstToGoal.isCumulative, isTrue);
      expect(RaceFormat.mostInWindow.isCumulative, isTrue);
      expect(RaceFormat.bestAttempt.isAttemptBased, isTrue);
      expect(RaceFormat.timedAttempt.isAttemptBased, isTrue);
      expect(RaceFormat.bestAttempt.isCumulative, isFalse);
    });

    test('scoring rule follows direction like scoringRuleForFormat', () {
      expect(
        RaceFormat.bestAttempt.scoringRuleFor('higher'),
        'maximum_attempt',
      );
      expect(
        RaceFormat.bestAttempt.scoringRuleFor('lower'),
        'minimum_attempt',
      );
      expect(
        RaceFormat.timedAttempt.scoringRuleFor('lower'),
        'minimum_attempt',
      );
      expect(RaceFormat.firstToGoal.scoringRuleFor('lower'), 'cumulative_sum');
      expect(
        RaceFormat.mostInWindow.scoringRuleFor('higher'),
        'cumulative_sum',
      );
    });
  });

  group('FIRST_TO_GOAL context', () {
    test('0/50 — the whole goal remains', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          targetValue: 50,
          participants: [participant(userId: 'me', score: 0)],
        ),
        'me',
      );
      expect(ctx.raceScoreBefore, 0);
      expect(ctx.remainingToGoal, 50);
      expect(ctx.statusLine, '50 to finish');
      expect(ctx.raceScoreAfter(5), 5);
    });

    test('20/50 — session adds onto the banked score, never restarts', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          targetValue: 50,
          participants: [
            participant(userId: 'me', score: 20),
            participant(userId: 'rival', score: 44),
          ],
        ),
        'me',
      );
      expect(ctx.remainingToGoal, 30);
      expect(ctx.statusLine, '30 to finish');
      expect(ctx.raceScoreAfter(5), 25);
      expect(ctx.completesGoal(29), isFalse);
      expect(ctx.completesGoal(30), isTrue);
    });

    test('49/50 — one more rep finishes', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          targetValue: 50,
          participants: [participant(userId: 'me', score: 49)],
        ),
        'me',
      );
      expect(ctx.remainingToGoal, 1);
      expect(ctx.statusLine, '1 more to finish');
      expect(ctx.completesGoal(1), isTrue);
    });

    test('completed race — no finish-the-goal flow', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          targetValue: 50,
          status: 'completed',
          participants: [participant(userId: 'me', score: 50)],
        ),
        'me',
      );
      expect(ctx.isFinished, isTrue);
      expect(ctx.remainingToGoal, 0);
      expect(ctx.statusLine, 'Goal reached');
    });
  });

  group('BEST_ATTEMPT higher-wins', () {
    test('no prior score — no fake target, no score to beat', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          format: 'best_attempt',
          scoringRule: 'maximum_attempt',
          participants: [participant(userId: 'me', score: 0)],
        ),
        'me',
      );
      expect(ctx.goalTarget, isNull);
      expect(ctx.remainingToGoal, isNull);
      expect(ctx.scoreToBeat, isNull);
      expect(ctx.statusLine, 'Best verified attempt wins');
      // Session result IS the score — max(), not addition.
      expect(ctx.raceScoreAfter(22), 22);
    });

    test('personal best + leader — score to beat is the leader', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          format: 'best_attempt',
          scoringRule: 'maximum_attempt',
          participants: [
            participant(userId: 'me', score: 18),
            participant(userId: 'rival', score: 25),
          ],
        ),
        'me',
      );
      expect(ctx.personalBest, 18);
      expect(ctx.leaderScore, 25);
      expect(ctx.scoreToBeat, 25);
      expect(ctx.statusLine, 'Beat 25');
      expect(ctx.beatsPersonalBest(22), isTrue);
      expect(ctx.beatsLeader(22), isFalse);
      expect(ctx.beatsLeader(28), isTrue);
      // A weak attempt never drags the banked best down.
      expect(ctx.raceScoreAfter(12), 18);
      expect(ctx.raceScoreAfter(28), 28);
    });

    test('viewer holds the best — score to beat is their own', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          format: 'best_attempt',
          scoringRule: 'maximum_attempt',
          participants: [
            participant(userId: 'me', score: 24),
            participant(userId: 'rival', score: 19),
          ],
        ),
        'me',
      );
      expect(ctx.scoreToBeat, 24);
      expect(ctx.statusLine, 'Beat your best: 24');
    });
  });

  group('BEST_ATTEMPT lower-wins (golf)', () {
    test('score to beat is the lowest rival score; lower wins', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          format: 'best_attempt',
          scoringRule: 'minimum_attempt',
          scoreDirection: 'lower',
          participants: [
            participant(userId: 'me', score: 80),
            participant(userId: 'rival', score: 74),
            participant(userId: 'rival2', score: 90),
          ],
        ),
        'me',
      );
      expect(ctx.leaderScore, 74);
      expect(ctx.scoreToBeat, 74);
      expect(ctx.statusLine, 'Go under 74');
      // Submitting 78 improves 80→78 but stays behind; 72 takes the lead.
      expect(ctx.raceScoreAfter(78), 78);
      expect(ctx.beatsPersonalBest(78), isTrue);
      expect(ctx.beatsLeader(78), isFalse);
      expect(ctx.beatsLeader(72), isTrue);
      // Worse attempts never replace the better banked score.
      expect(ctx.raceScoreAfter(88), 80);
    });
  });

  group('MOST_IN_WINDOW', () {
    test('accumulates; deadline + no score target', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          format: 'most_in_window',
          finishLineAt:
              DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String(),
          participants: [participant(userId: 'me', score: 14)],
        ),
        'me',
      );
      expect(ctx.isCumulative, isTrue);
      expect(ctx.goalTarget, isNull);
      expect(ctx.scoreToBeat, isNull);
      expect(ctx.deadline, isNotNull);
      expect(ctx.raceScoreAfter(6), 20);
      expect(
        ctx.statusLine,
        'Most verified score before the deadline wins',
      );
    });
  });

  group('TIMED_BATTLE', () {
    test('attempt duration + score to beat', () {
      final race = makeRace(
        format: 'timed_attempt',
        scoringRule: 'maximum_attempt',
        attemptDurationSeconds: 60,
        participants: [
          participant(userId: 'me', score: 0),
          participant(userId: 'rival', score: 31),
        ],
      );
      final ctx = VerifierRaceContext.forRace(race, 'me');
      expect(ctx.attemptDurationSeconds, 60);
      expect(ctx.scoreToBeat, 31);
      expect(ctx.statusLine, 'Beat 31');
    });
  });

  group('viewerContext (server truth) wins over participant rows', () {
    test('leader score comes from viewerContext when present', () {
      final ctx = VerifierRaceContext.forRace(
        makeRace(
          format: 'best_attempt',
          scoringRule: 'maximum_attempt',
          participants: [participant(userId: 'me', score: 10)],
          viewerContext: const RaceViewerContext(
            raceId: 'race-1',
            status: 'active',
            leaderUserId: 'rival',
            leaderScore: 33,
            viewerScore: 10,
            isMember: true,
          ),
        ),
        'me',
      );
      expect(ctx.leaderScore, 33);
      expect(ctx.scoreToBeat, 33);
    });
  });

  group('RaceDraft mode semantics', () {
    RaceDraft draft({required RaceFormat format}) => RaceDraft(
      title: '',
      activity: motionActivityDefinitions.firstWhere(
        (a) => a.supportedFormats.contains(format),
        orElse: () => motionActivityDefinitions.first,
      ),
      metric: RaceMetric.reps,
      format: format,
      targetValue: 50,
      finishLineAt: format == RaceFormat.mostInWindow
          ? '2026-10-07T00:00:00Z'
          : null,
      attemptDurationSeconds:
          format == RaceFormat.timedAttempt ? 60 : null,
    );

    test('validation is per-mode', () {
      expect(draft(format: RaceFormat.firstToGoal).isValidToCreate, isTrue);
      // No target needed — best attempt is valid at 0.
      final ba = draft(format: RaceFormat.bestAttempt)
          .copyWith(targetValue: 0);
      expect(ba.isValidToCreate, isTrue);
      // First-to-goal at 0 is not.
      expect(
        draft(format: RaceFormat.firstToGoal)
            .copyWith(targetValue: 0)
            .isValidToCreate,
        isFalse,
      );
      // most_in_window needs its finish line.
      expect(
        draft(format: RaceFormat.mostInWindow)
            .copyWith(clearTiming: true)
            .isValidToCreate,
        isFalse,
      );
      // timed needs a duration.
      expect(
        draft(format: RaceFormat.timedAttempt)
            .copyWith(clearAttemptFields: true)
            .isValidToCreate,
        isFalse,
      );
    });

    test('payload omits targetValue for non-target preset modes', () {
      final p = draft(format: RaceFormat.bestAttempt).toCreatePayload();
      expect(p.containsKey('targetValue'), isFalse);
      expect(p['format'], 'best_attempt');
      final ftg = draft(format: RaceFormat.firstToGoal).toCreatePayload();
      expect(ftg['targetValue'], 50);
    });

    test('generated titles follow the format', () {
      expect(
        draft(format: RaceFormat.firstToGoal).generatedTitleText,
        startsWith('First to 50'),
      );
      expect(
        draft(format: RaceFormat.bestAttempt).generatedTitleText,
        contains('attempt'),
      );
      expect(
        draft(format: RaceFormat.mostInWindow).generatedTitleText,
        startsWith('Most'),
      );
    });

    test('winStatement names the real rule', () {
      expect(
        draft(format: RaceFormat.firstToGoal).winStatement,
        contains('First to'),
      );
      expect(
        draft(format: RaceFormat.bestAttempt).winStatement,
        contains('Best single attempt'),
      );
      expect(
        draft(format: RaceFormat.bestAttempt)
            .copyWith(scoreDirection: 'lower')
            .winStatement,
        contains('Lowest'),
      );
      expect(
        draft(format: RaceFormat.mostInWindow).winStatement,
        contains('before the finish line'),
      );
      expect(
        draft(format: RaceFormat.timedAttempt).winStatement,
        contains('1 min'),
      );
    });

    test('mode switch clears stale attempt fields, keeps the finish line', () {
      final timed = draft(format: RaceFormat.timedAttempt)
          .copyWith(finishLineAt: '2026-10-07T00:00:00Z');
      final backToGoal = timed.copyWith(
        format: RaceFormat.firstToGoal,
        clearAttemptFields: true,
      );
      expect(backToGoal.attemptDurationSeconds, isNull);
      expect(backToGoal.attemptLimit, isNull);
      expect(backToGoal.finishLineAt, '2026-10-07T00:00:00Z');
    });
  });
}
