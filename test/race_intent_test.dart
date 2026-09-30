// Race Intent Engine — the table-driven interpretation corpus for the
// composer auto-decision rebuild.
//
// The contract: the user describes their race ONCE. The resolver turns the
// first phrase into structured intent; the composer asks only what is still
// missing. Three routing outcomes:
//
//   movement   — a catalog activity is justified by the whole phrase
//   customGoal — a structured non-movement goal (target/format/unit present)
//   ambiguous  — nothing safe to decide; the subject step must answer it
//
// False-match discipline: an alias *substring* never arms a movement, and a
// noun echo never fakes a custom unit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';
import 'package:nuvo/features/races/domain/race_intent.dart';
import 'package:nuvo/features/races/domain/race_name_interpreter.dart';

void main() {
  group('movement path', () {
    final cases = <String, String>{
      'Pushups': 'push_ups',
      'push ups': 'push_ups',
      'Push-ups': 'push_ups',
      '100 pushups': 'push_ups',
      'First to 50 pushups': 'push_ups',
      '50 squats': 'squats',
      'First to 20 jumping jacks': 'jumping_jacks',
      '2 minute plank': 'plank_hold',
      '120 second plank': 'plank_hold',
      'plank for 2 minutes': 'plank_hold',
      'Basketball shots': 'basketball_shot',
      'Make 10 basketball shots': 'basketball_shot',
      'Make 10 free throws': 'basketball_shot',
      'Squat challenge': 'squats',
      'Do 50 squats': 'squats',
    };
    for (final entry in cases.entries) {
      test('"${entry.key}" resolves ${entry.value}', () {
        final r = resolveRaceIntent(entry.key);
        expect(r.path, RaceIntentPath.movement, reason: r.reason);
        expect(r.activity?.activityId, entry.value);
        expect(r.interpretation.goalKind, RaceGoalKind.movement);
        expect(r.resolvesSubject, isTrue);
        expect(r.resolvedFields, contains(RaceField.activity));
      });
    }

    test('"100 pushups" carries the stated target', () {
      final r = resolveRaceIntent('100 pushups');
      expect(r.interpretation.targetValue, 100);
      expect(r.unresolvedFields, isNot(contains(RaceField.target)));
    });

    test('"First to 50 push ups" is cumulative higher-wins', () {
      final r = resolveRaceIntent('First to 50 push ups');
      expect(r.path, RaceIntentPath.movement);
      expect(r.interpretation.targetValue, 50);
      expect(r.interpretation.format, RaceFormat.firstToGoal);
      expect(r.interpretation.scoreDirection, 'higher');
    });

    test('"2 minute plank" is a 120-second goal, not a window', () {
      final r = resolveRaceIntent('2 minute plank');
      expect(r.activity?.activityId, 'plank_hold');
      expect(r.interpretation.targetValue, 120);
      expect(r.interpretation.metric, RaceMetric.seconds);
      // The duration IS the finish line — no stray attempt window.
      expect(r.interpretation.attemptDurationSeconds, isNull);
    });

    test('"plank for 2 minutes" lands the same way', () {
      final r = resolveRaceIntent('plank for 2 minutes');
      expect(r.activity?.activityId, 'plank_hold');
      expect(r.interpretation.targetValue, 120);
    });
  });

  group('custom goal path', () {
    final cases = <String>[
      'Read 5 books',
      'First to read 5 books',
      'Most books read',
      'Highest math grade',
      'Get a 95% in math',
      'Lowest golf score',
      'Fastest mile',
      'Study 10 hours',
      'Complete 20 coding problems',
      'Save \$500',
      'Read 100 pages',
      'Drink 8 glasses of water',
      'Most pages read',
      'Lowest mile time',
      'Finish 3 assignments',
      'first to run 5 miles',
      'Run 5 miles',
    ];
    for (final name in cases) {
      test('"$name" resolves customGoal', () {
        final r = resolveRaceIntent(name);
        expect(r.path, RaceIntentPath.customGoal, reason: r.reason);
        expect(r.interpretation.goalKind, RaceGoalKind.manual);
        expect(r.interpretation.activity, isNull);
        expect(r.resolvesSubject, isTrue);
      });
    }

    test('"Read 5 books" is a count to a finish line', () {
      final r = resolveRaceIntent('Read 5 books');
      expect(r.interpretation.targetValue, 5);
      expect(r.interpretation.manualUnit, 'books');
      expect(r.interpretation.format, RaceFormat.firstToGoal);
      expect(r.interpretation.scoreDirection, 'higher');
    });

    test('"Highest math grade" is a best-attempt percent', () {
      final r = resolveRaceIntent('Highest math grade');
      expect(r.interpretation.format, RaceFormat.bestAttempt);
      expect(r.interpretation.manualUnit, 'percent');
      expect(r.interpretation.scoreDirection, 'higher');
    });

    test('"Lowest golf score" flips the direction', () {
      final r = resolveRaceIntent('Lowest golf score');
      expect(r.interpretation.format, RaceFormat.bestAttempt);
      expect(r.interpretation.scoreDirection, 'lower');
    });

    test('"Fastest mile" measures the clock, lower wins', () {
      final r = resolveRaceIntent('Fastest mile');
      expect(r.interpretation.manualUnit, 'seconds');
      expect(r.interpretation.scoreDirection, 'lower');
    });
  });

  group('ambiguity — the resolver knows when it does not know', () {
    final cases = [
      'Summer challenge',
      'Get better',
      'Lock in',
      'Be productive',
      'Do stuff',
      'Challenge Noah',
      'Morning Mile',
    ];
    for (final name in cases) {
      test('"$name" stays ambiguous', () {
        final r = resolveRaceIntent(name);
        expect(r.path, RaceIntentPath.ambiguous, reason: r.reason);
        expect(r.resolvesSubject, isFalse);
      });
    }

    test('movement-shaped unknown ("do 20 dragon jumps") is ambiguous, '
        'not a fake custom goal', () {
      final r = resolveRaceIntent('do 20 dragon jumps');
      expect(r.path, RaceIntentPath.ambiguous);
      // And it never silently arms a verifier.
      expect(r.interpretation.goalKind, RaceGoalKind.manual);
    });
  });

  group('false matches — a substring is never a subject', () {
    final cases = [
      'Burpee backflip challenge',
      'Push my grades higher',
      'Planking a wall',
      'Squat building project',
    ];
    for (final name in cases) {
      test('"$name" arms no movement', () {
        final r = resolveRaceIntent(name);
        // Whatever the resolver decides, it is NOT a movement verdict —
        // the words are there, the intent is not.
        expect(r.path, isNot(RaceIntentPath.movement), reason: r.reason);
        expect(r.interpretation.activity, isNull);
      });
    }

    test('"Burpee backflip challenge" leaves the subject decision open', () {
      final r = resolveRaceIntent('Burpee backflip challenge');
      expect(r.path, RaceIntentPath.ambiguous);
    });
  });

  group('whole-phrase justification', () {
    test('filler framing still justifies', () {
      final pushups = motionActivityFromName('pushups')!;
      expect(activityJustifiedByName('first to 100 push ups', pushups), isTrue);
      expect(activityJustifiedByName('most pushups in a game', pushups), isTrue);
      expect(activityJustifiedByName('pushups by friday', pushups), isTrue);
    });

    test('a substantive leftover noun vetoes the match', () {
      final burpees = motionActivityFromName('burpees')!;
      expect(
        activityJustifiedByName('burpee backflip challenge', burpees),
        isFalse,
      );
      final squats = motionActivityFromName('squats')!;
      expect(
        activityJustifiedByName('squat building project', squats),
        isFalse,
      );
    });
  });

  group('remote catalog', () {
    MotionActivityDefinition starJump() => const MotionActivityDefinition(
          type: MotionActivityType.remote,
          backendId: 'star_jump',
          title: 'Star Jump',
          metric: RaceMetric.reps,
          suggestedTargets: [10, 20, 50],
          supportedFormats: [RaceFormat.firstToGoal],
          aliases: ['star jump', 'star jumps', 'starjumps'],
          proofLabel: 'star jumps',
          cameraInstruction: 'Full body in frame',
          instructions: ['Jump and spread your arms and legs.'],
          icon: Icons.star_rounded,
          framingLabel: 'Full body visible',
          preferredCameraView: PreferredCameraView.frontPreferred,
          category: MovementCategory.fullBody,
        );

    test('a remote alias resolves through the merged catalog', () {
      final catalog = [...motionActivityDefinitions, starJump()];
      final r = resolveRaceIntent('First to 30 star jumps', catalog: catalog);
      expect(r.path, RaceIntentPath.movement);
      expect(r.activity?.activityId, 'star_jump');
      expect(r.interpretation.targetValue, 30);
    });

    test('the bundled catalog alone does not know the remote movement', () {
      final r = resolveRaceIntent('First to 30 star jumps');
      expect(r.path, isNot(RaceIntentPath.movement));
    });
  });

  group('provenance', () {
    test('resolved fields are marked inferred; unresolved stay open', () {
      final r = resolveRaceIntent('Pushups');
      expect(r.resolvedFields, contains(RaceField.activity));
      // No stated target — the goal step owns that question.
      expect(r.interpretation.question, isNotNull);
      final resolved100 = resolveRaceIntent('100 pushups');
      expect(resolved100.resolvedFields, contains(RaceField.target));
      expect(resolved100.unresolvedFields, isNot(contains(RaceField.target)));
    });
  });
}
