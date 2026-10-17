import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';

Race _race(String title, String format) => Race(
  id: 'r1',
  creatorId: 'u1',
  title: title,
  goalType: format,
  unit: 'reps',
  activityId: 'push_ups',
  metric: 'reps',
  format: format,
  scoringRule: 'cumulative_sum',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  participants: const [],
  finalStandings: const [],
);

void main() {
  final pushups = motionActivityForType(MotionActivityType.pushUps)!;
  final finish = DateTime.now().toUtc().add(const Duration(days: 2));

  // Every win condition must be creatable from a preset movement. A race that
  // is not 'first to goal' sends no goal number, and the creator must accept
  // that instead of crashing on a null cast.
  for (final format in RaceFormat.values) {
    test('preset ${format.backendValue} race builds its request without a goal '
        'crash', () async {
      final draft = RaceDraft(
        title: '',
        hasCustomName: false,
        activity: pushups,
        metric: RaceMetric.reps,
        format: format,
        targetValue: format == RaceFormat.firstToGoal ? 20 : 0,
        finishLineAt: format == RaceFormat.firstToGoal
            ? null
            : finish.toIso8601String(),
        attemptDurationSeconds: format == RaceFormat.timedAttempt ? 60 : null,
      );
      int? sentTarget = -1;
      String? sentFormat;
      final race = await createRaceForComposerDraft(
        draft: draft,
        createCustomRace:
            ({
              required title,
              targetValue,
              required customActivityName,
              verifierSpec,
              motionV2Spec,
              format = 'first_to_goal',
              finishLineAt,
              attemptDurationSeconds,
              attemptLimit,
              scoreDirection,
            }) async => fail('preset race must not use the custom creator'),
        createRace:
            ({
              required title,
              description,
              category,
              goalType = 'manual',
              targetValue,
              unit,
              proofRequirement,
              proofReviewMode,
              aiActivityType,
              activityId,
              metric,
              format,
              recurrence,
              targetUnit,
              proofMode,
              scoreDirection,
            }) async {
              sentTarget = targetValue;
              sentFormat = format;
              return _race(title, format ?? 'first_to_goal');
            },
      );
      expect(race.id, 'r1');
      expect(sentFormat, format.backendValue);
      if (format == RaceFormat.firstToGoal) {
        expect(sentTarget, 20);
      } else {
        expect(sentTarget, isNull);
      }
    });
  }

  // The same must hold for manual (honor-system) goals in every win condition.
  for (final format in RaceFormat.values) {
    test('manual ${format.backendValue} race builds its request', () async {
      final draft = RaceDraft(
        title: 'Read pages',
        hasCustomName: true,
        activity: pushups,
        metric: RaceMetric.reps,
        format: format,
        goalKind: RaceGoalKind.manual,
        manualGoalName: 'Pages read',
        manualUnit: 'pages',
        targetValue: format == RaceFormat.firstToGoal ? 50 : 0,
        finishLineAt: format == RaceFormat.firstToGoal
            ? null
            : finish.toIso8601String(),
        attemptDurationSeconds: format == RaceFormat.timedAttempt ? 60 : null,
      );
      String? sentFormat;
      String? sentUnit;
      final race = await createRaceForComposerDraft(
        draft: draft,
        createCustomRace:
            ({
              required title,
              targetValue,
              required customActivityName,
              verifierSpec,
              motionV2Spec,
              format = 'first_to_goal',
              finishLineAt,
              attemptDurationSeconds,
              attemptLimit,
              scoreDirection,
            }) async => fail('manual race must not use the custom creator'),
        createRace:
            ({
              required title,
              description,
              category,
              goalType = 'manual',
              targetValue,
              unit,
              proofRequirement,
              proofReviewMode,
              aiActivityType,
              activityId,
              metric,
              format,
              recurrence,
              targetUnit,
              proofMode,
              scoreDirection,
            }) async {
              sentFormat = format;
              sentUnit = unit;
              return _race(title, format ?? 'first_to_goal');
            },
      );
      expect(race.id, 'r1');
      expect(sentFormat, format.backendValue);
      expect(sentUnit, 'pages');
    });
  }
}
