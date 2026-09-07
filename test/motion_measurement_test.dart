import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';

/// Contextual units — the activity catalog owns the measurement model, and the
/// composer / race display / progress all read it from one place. See
/// docs/agents/14 §L and the Motion Intelligence PRD §13–17.

void main() {
  group('duration formatters', () {
    test('formatClock', () {
      expect(formatClock(0), '0:00');
      expect(formatClock(45), '0:45');
      expect(formatClock(60), '1:00');
      expect(formatClock(90), '1:30');
      expect(formatClock(305), '5:05');
    });

    test('formatDurationShort — compact, for chips', () {
      expect(formatDurationShort(30), '30s');
      expect(formatDurationShort(45), '45s');
      expect(formatDurationShort(60), '1 min');
      expect(formatDurationShort(120), '2 min');
      expect(formatDurationShort(90), '1:30');
      expect(formatDurationShort(600), '10 min');
    });

    test('formatDurationLong — spoken, for the win statement', () {
      expect(formatDurationLong(1), '1 second');
      expect(formatDurationLong(45), '45 seconds');
      expect(formatDurationLong(60), '1 minute');
      expect(formatDurationLong(120), '2 minutes');
      expect(formatDurationLong(90), '1m 30s');
    });
  });

  group('measurement type mapping', () {
    test('serialization stays on RaceMetric (Worker only accepts reps|seconds)',
        () {
      expect(MotionMeasurementType.repetitions.raceMetric, RaceMetric.reps);
      expect(MotionMeasurementType.duration.raceMetric, RaceMetric.seconds);
      expect(
        MotionMeasurementType.fromRaceMetric(RaceMetric.seconds),
        MotionMeasurementType.duration,
      );
      expect(
        MotionMeasurementType.fromRaceMetric(RaceMetric.reps),
        MotionMeasurementType.repetitions,
      );
    });

    test('formatMotionTarget / formatMotionProgress / formatMotionGoalOption',
        () {
      expect(formatMotionTarget(MotionMeasurementType.repetitions, 25, 'reps'),
          '25 reps');
      expect(formatMotionTarget(MotionMeasurementType.repetitions, 40, 'steps'),
          '40 steps');
      expect(
          formatMotionTarget(MotionMeasurementType.duration, 120, 'seconds'),
          '2 minutes');

      expect(
        formatMotionProgress(MotionMeasurementType.repetitions, 12, 25, 'reps'),
        '12 / 25 reps',
      );
      expect(
        formatMotionProgress(MotionMeasurementType.duration, 45, 120, 'seconds'),
        '0:45 / 2:00',
      );

      expect(formatMotionGoalOption(MotionMeasurementType.repetitions, 25), '25');
      expect(formatMotionGoalOption(MotionMeasurementType.duration, 90), '1:30');
    });
  });

  group('every catalog preset has a sane measurement model', () {
    for (final def in motionActivityDefinitions) {
      final id = def.type.backendValue;
      test(id, () {
        // resolves without throwing
        final type = def.resolvedMeasurementType;
        // serialization is consistent with the wire metric
        expect(type.raceMetric, def.metric,
            reason: '$id: measurement type disagrees with metric');
        // display strings are populated and not a raw enum name
        expect(def.unit.trim(), isNotEmpty, reason: '$id: empty unit');
        expect(def.goalPrompt.trim(), isNotEmpty, reason: '$id: empty prompt');
        expect(def.goalPrompt, isNot(contains('null')), reason: '$id: prompt');
        expect(def.goalPrompt.endsWith('?'), isTrue,
            reason: '$id: goal prompt should be a question: "${def.goalPrompt}"');
        // target/progress format without error for a representative value
        expect(def.targetLabel(def.defaultTarget), isNotEmpty);
        expect(def.counterLabel(0, def.defaultTarget), contains('/'));
      });
    }

    test('plank is a duration and asks "How long?"', () {
      final plank = motionActivityForType(MotionActivityType.plankHold)!;
      expect(plank.resolvedMeasurementType, MotionMeasurementType.duration);
      expect(plank.goalPrompt, 'How long?');
      expect(plank.targetLabel(120), '2 minutes');
      expect(plank.counterLabel(45, 120), '0:45 / 2:00');
    });

    test('gait movements measure in steps, not reps', () {
      for (final t in [
        MotionActivityType.runningInPlace,
        MotionActivityType.walkingInPlace,
        MotionActivityType.marchingInPlace,
        MotionActivityType.treadmillRunning,
      ]) {
        final def = motionActivityForType(t)!;
        expect(def.unit, 'steps', reason: t.name);
        expect(def.goalPrompt, 'How many steps?', reason: t.name);
        expect(def.targetLabel(50), '50 steps', reason: t.name);
        // still serializes as reps
        expect(def.resolvedMeasurementType.raceMetric, RaceMetric.reps,
            reason: t.name);
      }
    });

    test('pushups still ask "How many pushups?" and count reps', () {
      final p = motionActivityForType(MotionActivityType.pushUps)!;
      expect(p.goalPrompt, 'How many pushups?');
      expect(p.unit, 'reps');
      expect(p.targetLabel(25), '25 reps');
    });
  });
}
