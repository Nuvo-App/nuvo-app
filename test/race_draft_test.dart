import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';

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

    test('does not silently fall back for unsupported activities', () {
      expect(draftFromIdea('First to 10 burpees'), isNull);
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
  });
}
