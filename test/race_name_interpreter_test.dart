import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';
import 'package:nuvo/features/races/domain/race_name_interpreter.dart';

MotionActivityDefinition _preset(MotionActivityType t) =>
    motionActivityForType(t)!;

RaceDraft _interpretedDraft(String title) =>
    mergeRaceNameInterpretation(
      draftForActivity(_preset(MotionActivityType.pushUps)),
      interpretRaceName(title),
    );

void main() {
  group('interpretRaceName — preset subjects', () {
    test('"First to 20 jumping jacks"', () {
      final i = interpretRaceName('First to 20 jumping jacks');
      expect(i.activity?.type, MotionActivityType.jumpingJacks);
      expect(i.metric, RaceMetric.reps);
      expect(i.format, RaceFormat.firstToGoal);
      expect(i.targetValue, 20);
      expect(i.proofNeed, ProofNeed.motionReps);
      expect(i.goalKind, RaceGoalKind.movement);
      expect(i.confidence, InterpretationConfidence.high);
    });

    test('"First to 100 pushups"', () {
      final i = interpretRaceName('First to 100 pushups');
      expect(i.activity?.type, MotionActivityType.pushUps);
      expect(i.targetValue, 100);
      expect(i.format, RaceFormat.firstToGoal);
    });

    test('"Most jumping jacks in 30 seconds"', () {
      final i = interpretRaceName('Most jumping jacks in 30 seconds');
      expect(i.activity?.type, MotionActivityType.jumpingJacks);
      expect(i.metric, RaceMetric.reps);
      expect(i.format, RaceFormat.timedAttempt);
      expect(i.attemptDurationSeconds, 30);
      expect(i.proofNeed, ProofNeed.motionReps);
      // The duration must not leak into the rep target.
      expect(i.targetValue, isNot(30));
    });

    test('"Most jumping jacks in 2 minutes" converts units', () {
      final i = interpretRaceName('Most jumping jacks in 2 minutes');
      expect(i.attemptDurationSeconds, 120);
    });

    test('"Longest plank"', () {
      final i = interpretRaceName('Longest plank');
      expect(i.activity?.type, MotionActivityType.plankHold);
      expect(i.metric, RaceMetric.seconds);
      expect(i.format, RaceFormat.bestAttempt);
      expect(i.proofNeed, ProofNeed.motionDuration);
    });

    test('"Most basketball shots in 60 seconds" degrades to a supported format',
        () {
      final i = interpretRaceName('Most basketball shots in 60 seconds');
      expect(i.activity?.type, MotionActivityType.basketballShot);
      expect(i.attemptDurationSeconds, 60);
      // Basketball shot does not support timed_attempt — the interpreter
      // must degrade to a supported format and say so, not force it.
      expect(i.activity!.supportedFormats, contains(i.format));
      expect(i.assumptions, isNotEmpty);
    });
  });

  group('interpretRaceName — custom subjects', () {
    test('"Fastest mile"', () {
      final i = interpretRaceName('Fastest mile');
      expect(i.activity, isNull);
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.metric, RaceMetric.seconds);
      expect(i.format, RaceFormat.bestAttempt);
      expect(i.manualGoalName, 'Mile');
      expect(i.manualUnit, 'seconds');
      expect(i.proofNeed, ProofNeed.timeResult);
      // Fastest = lowest time wins — a real scoring primitive, not a flag.
      expect(i.scoreDirection, 'lower');
    });

    test('"Highest math test grade"', () {
      final i = interpretRaceName('Highest math test grade');
      expect(i.activity, isNull);
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.manualGoalName, 'Math Test Grade');
      expect(i.manualUnit, 'percent');
      expect(i.format, RaceFormat.bestAttempt);
      expect(i.proofNeed, ProofNeed.numeric);
      expect(i.confidence, InterpretationConfidence.assumed);
    });

    test('"Lowest golf score"', () {
      final i = interpretRaceName('Lowest golf score');
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.format, RaceFormat.bestAttempt);
      expect(i.manualUnit, 'strokes');
      // Lower-wins is a real scoring primitive — no assumption, no flag.
      expect(i.scoreDirection, 'lower');
      expect(i.assumptions.join(' '), isNot(contains('Lowest')));
    });

    test('"Fastest mile" also scores lower-wins', () {
      final i = interpretRaceName('Fastest mile');
      expect(i.scoreDirection, 'lower');
      expect(i.format, RaceFormat.bestAttempt);
    });

    test('a re-interpreted "highest" title flips direction back', () {
      var draft = RaceDraft(
        title: 'Lowest golf score',
        activity: motionActivityDefinitions.first,
        metric: RaceMetric.reps,
        format: RaceFormat.bestAttempt,
        targetValue: 100,
        goalKind: RaceGoalKind.manual,
        manualGoalName: 'Golf score',
        manualUnit: 'strokes',
        scoreDirection: 'lower',
      );
      draft = mergeRaceNameInterpretation(
        draft,
        interpretRaceName('Highest bench press'),
      );
      expect(draft.scoreDirection, 'higher');
    });

    test('"Most pages read by Friday"', () {
      final i = interpretRaceName('Most pages read by Friday');
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.format, RaceFormat.mostInWindow);
      expect(i.manualUnit, 'pages');
      expect(i.manualGoalName, isNot(contains('Friday')));
      // Never invent a deadline — surfaced as an assumption instead.
      expect(i.assumptions.join(' '), contains('Finish line'));
    });

    test('"First to read 5 books"', () {
      final i = interpretRaceName('First to read 5 books');
      expect(i.format, RaceFormat.firstToGoal);
      expect(i.targetValue, 5);
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.manualUnit, 'pages');
    });

    test('"Most steps today"', () {
      final i = interpretRaceName('Most steps today');
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.format, RaceFormat.mostInWindow);
      expect(i.manualUnit, 'steps');
    });

    test('"Highest bench press"', () {
      final i = interpretRaceName('Highest bench press');
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.manualUnit, 'lbs');
    });

    test('"Longest wall sit"', () {
      final i = interpretRaceName('Longest wall sit');
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.metric, RaceMetric.seconds);
      expect(i.manualUnit, 'seconds');
    });

    test('"Most coding problems this week"', () {
      final i = interpretRaceName('Most coding problems this week');
      expect(i.goalKind, RaceGoalKind.manual);
      expect(i.format, RaceFormat.mostInWindow);
      expect(i.manualUnit, 'problems');
    });
  });

  group('interpretRaceName — ambiguity and number words', () {
    test('"running challenge" does not invent configuration', () {
      final i = interpretRaceName('running challenge');
      // The subject is understood (running is a catalog alias); nothing else
      // is invented — the default target is flagged, one question is asked.
      expect(i.activity?.type, MotionActivityType.runningInPlace);
      expect(i.format, RaceFormat.firstToGoal);
      expect(i.attemptDurationSeconds, isNull);
      expect(i.assumptions, isNotEmpty);
      expect(i.question, isNotNull);
      expect(i.confidence, InterpretationConfidence.assumed);
    });

    test('"First to twenty pushups" reads number words', () {
      final i = interpretRaceName('First to twenty pushups');
      expect(i.activity?.type, MotionActivityType.pushUps);
      expect(i.targetValue, 20);
    });
  });

  group('mergeRaceNameInterpretation — user edit wins', () {
    test('user-edited target survives a later title interpretation', () {
      // 1. Title interpreted → target 20 inferred.
      var draft = _interpretedDraft('First to 20 pushups');
      expect(draft.targetValue, 20);
      // 2. User changes target to 30.
      draft = draft.copyWith(
        targetValue: 30,
        markEdited: {RaceField.target},
      );
      // 3. Title changes slightly; interpretation runs again.
      draft = mergeRaceNameInterpretation(
        draft.copyWith(
          title: 'First to 20 pushups with Riley',
          hasCustomName: true,
          markEdited: {RaceField.title},
        ),
        interpretRaceName('First to 20 pushups with Riley'),
      );
      // 4. USER EDIT WINS — target stays 30.
      expect(draft.targetValue, 30);
      expect(draft.activity.type, MotionActivityType.pushUps);
    });

    test('user-picked activity survives re-interpretation', () {
      var draft = _interpretedDraft('First to 20 pushups');
      expect(draft.activity.type, MotionActivityType.pushUps);
      // User switches to squats on the activity step.
      draft = draft
          .asPreset(activity: _preset(MotionActivityType.squats))
          .copyWith(markEdited: {RaceField.activity});
      // Same title committed again → interpretation must not revert it.
      draft = mergeRaceNameInterpretation(
        draft,
        interpretRaceName('First to 20 pushups'),
      );
      expect(draft.activity.type, MotionActivityType.squats);
    });

    test('un-edited fields still re-interpret freely', () {
      var draft = _interpretedDraft('First to 20 pushups');
      // No user edits — a new title may change everything it inferred.
      draft = mergeRaceNameInterpretation(
        draft,
        interpretRaceName('Most jumping jacks in 30 seconds'),
      );
      expect(draft.activity.type, MotionActivityType.jumpingJacks);
      expect(draft.format, RaceFormat.timedAttempt);
      expect(draft.attemptDurationSeconds, 30);
    });

    test('user-set timing survives a non-timed title', () {
      var draft = _interpretedDraft('First to 20 pushups');
      draft = draft.copyWith(
        format: RaceFormat.timedAttempt,
        attemptDurationSeconds: 90,
        markEdited: {RaceField.format, RaceField.timing},
      );
      draft = mergeRaceNameInterpretation(
        draft,
        interpretRaceName('First to 50 squats'),
      );
      expect(draft.attemptDurationSeconds, 90);
    });
  });

  group('intent phrasing', () {
    test('"Who can get the highest grades?" parses like "highest grades"', () {
      final direct = interpretRaceName('highest grades');
      final phrased = interpretRaceName('Who can get the highest grades?');
      expect(phrased.format, direct.format);
      expect(phrased.manualUnit, direct.manualUnit);
      expect(phrased.goalKind, direct.goalKind);
      expect(phrased.format, RaceFormat.bestAttempt);
    });

    test('"Who can do the most pushups" still resolves the activity', () {
      final i = interpretRaceName('Who can do the most pushups');
      expect(i.activity?.type, MotionActivityType.pushUps);
      expect(i.format, RaceFormat.mostInWindow);
    });

    test('"let\'s see who can do 50 pushups" falls back to subject+target', () {
      final i = interpretRaceName("let's see who can do 50 pushups");
      expect(i.activity?.type, MotionActivityType.pushUps);
      expect(i.targetValue, 50);
    });
  });
}
