import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';
import 'package:nuvo/features/races/domain/race_mode_semantics.dart';
import 'package:nuvo/features/races/domain/race_name_interpreter.dart';

void main() {
  group('Race System V2 draft parsing', () {
    test('parses arbitrary first-to-goal pushup targets', () {
      final six = draftFromIdea('First to 6 pushups');
      final fifteen = draftFromIdea('First to 15 pushups');
      final hundred = draftFromIdea('First to 100 pushups');

      expect(six?.activity.type, MotionActivityType.pushUps);
      expect(six?.metric, RaceMetric.reps);
      expect(six?.format, RaceFormat.firstToGoal);
      expect(six?.targetValue, 6);

      expect(fifteen?.targetValue, 15);
      expect(hundred?.targetValue, 100);
    });

    test('keeps activity separate from metric', () {
      final squats = draftFromIdea('First to 25 squats');
      final plank = draftFromIdea('First to 600 plank seconds');

      expect(squats?.activity.type.backendValue, 'squats');
      expect(squats?.metric.backendValue, 'reps');

      expect(plank?.activity.type.backendValue, 'plank_hold');
      expect(plank?.metric.backendValue, 'seconds');
    });

    test('unsupported activities become a custom race, never a preset', () {
      final d = draftFromIdea('First to 10 cartwheels');
      expect(d, isNotNull);
      expect(d!.goalKind, RaceGoalKind.manual);
      expect(d.manualGoalName, isNotEmpty);
    });

    test('templates emit one shared structured create payload', () {
      final draft = draftFromIdea('First to 100 Pushups')!;
      final payload = draft.toCreatePayload();

      expect(payload['activityId'], 'push_ups');
      expect(payload['metric'], 'reps');
      expect(payload['format'], 'first_to_goal');
      expect(payload['targetValue'], 100);
      expect(payload['proofRequirement'], 'ai_check');
    });

    test('quick start prefill for squats uses correct activity and metric', () {
      final draft = draftFromIdea('First to 25 squats')!;
      expect(draft.activity.type, MotionActivityType.squats);
      expect(draft.metric, RaceMetric.reps);
      expect(draft.targetValue, 25);
      expect(draft.format, RaceFormat.firstToGoal);
    });

    test('quick start prefill for plank uses seconds metric', () {
      final draft = draftFromIdea('First to 300 plank seconds')!;
      expect(draft.activity.type, MotionActivityType.plankHold);
      expect(draft.metric, RaceMetric.seconds);
      expect(draft.targetValue, 300);
    });

    test('quick start payload is editable via copyWith', () {
      final draft = draftFromIdea('First to 15 pushups')!;
      expect(draft.targetValue, 15);

      final edited = draft.copyWith(targetValue: 50);
      expect(edited.targetValue, 50);
      expect(edited.activity.type, MotionActivityType.pushUps);
      expect(edited.metric, RaceMetric.reps);
    });

    test('copyWith preserves activity metric when changing target only', () {
      final plank = draftFromIdea('First to 60 plank seconds')!;
      final edited = plank.copyWith(targetValue: 120);
      expect(edited.metric, RaceMetric.seconds);
      expect(edited.activity.type, MotionActivityType.plankHold);
    });

    test('plank target label formats as a clock time, not reps', () {
      final plank = motionActivityForType(MotionActivityType.plankHold)!;
      expect(plank.targetLabel(60), '1 minute');
      expect(plank.targetLabel(300), '5 minutes');
    });

    test('pushup target label formats as reps', () {
      final pushups = motionActivityForType(MotionActivityType.pushUps)!;
      expect(pushups.targetLabel(15), '15 reps');
    });

    test('plank counter label shows a clock time', () {
      final plank = motionActivityForType(MotionActivityType.plankHold)!;
      expect(plank.counterLabel(45, 60), '0:45 / 1:00');
    });

    test('squats counter label shows reps', () {
      final squats = motionActivityForType(MotionActivityType.squats)!;
      expect(squats.counterLabel(10, 25), '10 / 25 reps');
    });

    test('draftForActivity uses activity defaultTarget', () {
      final plank = motionActivityForType(MotionActivityType.plankHold)!;
      final draft = draftForActivity(plank);
      expect(draft.targetValue, plank.defaultTarget);
      expect(draft.metric, RaceMetric.seconds);
    });

    test('toCreatePayload for plank emits seconds metric', () {
      final draft = draftFromIdea('First to 300 plank seconds')!;
      final payload = draft.toCreatePayload();
      expect(payload['activityId'], 'plank_hold');
      expect(payload['metric'], 'seconds');
      expect(payload['targetUnit'], 'seconds');
      expect(payload['targetValue'], 300);
    });

    test('parsing idea with no number uses activity default target', () {
      final draft = draftFromIdea('pushups race');
      expect(draft, isNotNull);
      expect(draft!.targetValue, greaterThan(0));
    });

    test('first-to-goal payload stays free of timing fields', () {
      final payload = draftFromIdea('First to 100 pushups')!.toCreatePayload();
      expect(payload.containsKey('finishLineAt'), isFalse);
      expect(payload.containsKey('attemptDurationSeconds'), isFalse);
      expect(payload.containsKey('attemptLimit'), isFalse);
    });

    test('deadline modes emit finishLineAt + attempt fields on the wire', () {
      final base = draftFromIdea('First to 100 pushups')!;
      final deadline = DateTime.utc(2026, 10, 1).toIso8601String();

      final most = base.copyWith(
        format: RaceFormat.mostInWindow,
        finishLineAt: deadline,
      );
      expect(most.toCreatePayload()['format'], 'most_in_window');
      expect(most.toCreatePayload()['finishLineAt'], deadline);

      final battle = base.copyWith(
        format: RaceFormat.timedAttempt,
        finishLineAt: deadline,
        attemptDurationSeconds: 60,
        attemptLimit: 3,
      );
      final payload = battle.toCreatePayload();
      expect(payload['format'], 'timed_attempt');
      expect(payload['finishLineAt'], deadline);
      expect(payload['attemptDurationSeconds'], 60);
      expect(payload['attemptLimit'], 3);
    });

    test('test_gap13_manual_timed_draft_clamps', () {
      // Interpreted manual goals can't be attempt formats — there is no
      // camera attempt. They clamp to Most total, keeping a finish line.
      final timed = draftFromIdea('Most cartwheels in 30 seconds')!;
      expect(timed.isManual, isTrue);
      expect(timed.format, RaceFormat.mostInWindow);

      final best = draftFromIdea('Lowest golf score')!;
      expect(best.isManual, isTrue);
      expect(best.format.isAttemptBased, isFalse);

      // A deadline survives the clamp — a finish line is never dropped.
      final deadline = draftFromIdea('Most books by Friday')!;
      expect(deadline.isManual, isTrue);
      expect(deadline.format, RaceFormat.mostInWindow);
      expect(deadline.finishLineAt, isNotNull);

      // The merge path clamps too: typing an attempt-shaped name while on
      // a manual draft must not leave an attempt format standing.
      var d = RaceDraft(
        title: 'x',
        activity: motionActivityDefinitions.first,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 1,
        goalKind: RaceGoalKind.manual,
        manualGoalName: 'Read',
        manualUnit: 'pages',
      );
      d = mergeRaceNameInterpretation(
        d,
        interpretRaceName('Most cartwheels in 30 seconds'),
      );
      expect(d.isManual, isTrue);
      expect(d.format, RaceFormat.mostInWindow);

      // Preset activities keep every format — clamping is manual-only.
      final preset = draftFromIdea('Most jumping jacks in 30 seconds')!;
      expect(preset.isManual, isFalse);
      expect(preset.format, RaceFormat.timedAttempt);
    });

    test('test_gapN11_deadline_modes_require_finish_line', () {
      final base = draftFromIdea('First to 100 pushups')!;
      final deadline = DateTime.utc(2026, 10, 1).toIso8601String();

      // First to stays finish-line free — still valid with none set.
      expect(base.finishLineAt, isNull);
      expect(base.isValidToCreate, isTrue);

      for (final format in [
        RaceFormat.mostInWindow,
        RaceFormat.bestAttempt,
        RaceFormat.timedAttempt,
      ]) {
        final noLine = base.copyWith(format: format);
        expect(
          noLine.isValidToCreate,
          isFalse,
          reason: '$format without a finish line',
        );
        final withLine = noLine.copyWith(
          finishLineAt: deadline,
          attemptDurationSeconds:
              format == RaceFormat.timedAttempt ? 60 : null,
        );
        expect(
          withLine.isValidToCreate,
          isTrue,
          reason: '$format with a finish line',
        );
      }
    });

    test('test_gapN11_review_copy_per_mode', () {
      final deadline = DateTime.utc(2026, 10, 1).toIso8601String();
      final base = draftFromIdea('First to 100 pushups')!;
      final statements = <RaceFormat, String>{};
      statements[RaceFormat.firstToGoal] = base.winStatement;
      statements[RaceFormat.mostInWindow] = base
          .copyWith(format: RaceFormat.mostInWindow, finishLineAt: deadline)
          .winStatement;
      statements[RaceFormat.bestAttempt] = base
          .copyWith(format: RaceFormat.bestAttempt, finishLineAt: deadline)
          .winStatement;
      statements[RaceFormat.timedAttempt] = base
          .copyWith(
            format: RaceFormat.timedAttempt,
            finishLineAt: deadline,
            attemptDurationSeconds: 30,
          )
          .winStatement;

      // Every mode wins a different way — the review page must say so.
      expect(statements.values.toSet(), hasLength(4));
      expect(statements[RaceFormat.firstToGoal], contains('First to'));
      expect(
        statements[RaceFormat.mostInWindow],
        contains('Highest total'),
      );
      expect(
        statements[RaceFormat.bestAttempt],
        contains('Best single attempt'),
      );
      expect(statements[RaceFormat.timedAttempt], contains('30s'));

      // Direction is part of the rule for attempt formats.
      final lowerBest = base
          .copyWith(
            format: RaceFormat.bestAttempt,
            finishLineAt: deadline,
            scoreDirection: 'lower',
          )
          .winStatement;
      expect(lowerBest, contains('Lowest'));
      final lowerTimed = base
          .copyWith(
            format: RaceFormat.timedAttempt,
            finishLineAt: deadline,
            attemptDurationSeconds: 30,
            scoreDirection: 'lower',
          )
          .winStatement;
      expect(lowerTimed, contains('Least'));
      expect(lowerTimed, contains('30s'));
    });

    test('test_gap5_timed_battle_without_duration_invalid', () {
      final deadline = DateTime.utc(2026, 10, 1).toIso8601String();
      final battle = draftFromIdea('First to 100 pushups')!.copyWith(
        format: RaceFormat.timedAttempt,
        finishLineAt: deadline,
      );
      expect(battle.attemptDurationSeconds, isNull);
      expect(battle.isValidToCreate, isFalse);
      expect(
        battle.copyWith(attemptDurationSeconds: 30).isValidToCreate,
        isTrue,
      );
    });

    test('clearTiming resets deadline + attempt fields', () {
      final deadline = DateTime.utc(2026, 10, 1).toIso8601String();
      final timed = draftFromIdea('First to 100 pushups')!.copyWith(
        format: RaceFormat.timedAttempt,
        finishLineAt: deadline,
        attemptDurationSeconds: 60,
      );
      final back = timed.copyWith(
        format: RaceFormat.firstToGoal,
        clearTiming: true,
      );
      expect(back.format, RaceFormat.firstToGoal);
      expect(back.finishLineAt, isNull);
      expect(back.attemptDurationSeconds, isNull);
      expect(back.toCreatePayload().containsKey('finishLineAt'), isFalse);
    });
  });

  group('Race System V2 activity catalog invariants', () {
    test('plank is the only activity with seconds metric', () {
      for (final def in motionActivityDefinitions) {
        if (def.type == MotionActivityType.plankHold) {
          expect(def.metric, RaceMetric.seconds);
        } else {
          expect(def.metric, RaceMetric.reps);
        }
      }
    });

    test('all supported activities have at least one suggested target', () {
      for (final def in motionActivityDefinitions) {
        expect(
          def.suggestedTargets,
          isNotEmpty,
          reason: '${def.title} must have suggested targets',
        );
      }
    });

    test('all supported activities have firstToGoal in supportedFormats', () {
      for (final def in motionActivityDefinitions) {
        expect(
          def.supportedFormats,
          contains(RaceFormat.firstToGoal),
          reason: '${def.title} must support first_to_goal',
        );
      }
    });

    test('no duplicate activity type entries in catalog', () {
      final types = motionActivityDefinitions.map((d) => d.type).toList();
      final unique = types.toSet();
      expect(
        types.length,
        unique.length,
        reason: 'catalog must not have duplicate entries',
      );
    });
  });
    test('interpreted deadline fills the finish line; questions surface', () {
      var d = RaceDraft(
        title: 'x',
        activity: motionActivityDefinitions.first,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 1,
      );
      d = mergeRaceNameInterpretation(
          d, interpretRaceName('Most books by Friday'));
      expect(d.finishLineAt, isNotNull);

      d = mergeRaceNameInterpretation(
          d, interpretRaceName('Who can go the farthest'));
      expect(d.clarification, isNotNull);

      // A clean title clears the stale question.
      d = mergeRaceNameInterpretation(
          d, interpretRaceName('First to 100 pushups'));
      expect(d.clarification, isNull);

      // A timed attempt clears the stale inferred finish line.
      d = mergeRaceNameInterpretation(
          d, interpretRaceName('Most jumping jacks in 30 seconds'));
      expect(d.attemptDurationSeconds, 30);
      expect(d.finishLineAt, isNull);
    });
}
