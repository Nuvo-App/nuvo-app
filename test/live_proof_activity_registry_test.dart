import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/live_proof_activity_registry.dart';
import 'package:nuvo/features/races/ai/live_proof_models.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';

void main() {
  test('live proof registry exposes current camera-verified activities', () {
    final activityIds = liveProofActivityDefinitions
        .map((definition) => definition.activityId)
        .toSet();

    expect(activityIds, contains('push_ups'));
    expect(activityIds, contains('squats'));
    expect(activityIds, contains('jumping_jacks'));
    expect(activityIds, contains('lunges'));
    expect(activityIds, contains('plank_hold'));
  });

  test('live proof registry maps activities to pose validators', () {
    final pushups = liveProofActivityForId('push_ups');

    expect(pushups, isNotNull);
    expect(pushups!.metric, RaceMetric.reps);
    expect(pushups.requiredSignals, contains(LiveProofSignalType.pose));
    expect(pushups.createValidator, isNotNull);
  });

  test('jumping jacks backend id does not fall back to pushups', () {
    expect(
      AiMotionActivity.fromBackendValue('jumping_jacks'),
      AiMotionActivity.jumpingJacks,
    );
    expect(
      AiMotionActivity.fromBackendValue('Jumping Jacks'),
      AiMotionActivity.jumpingJacks,
    );
    expect(
      MotionActivityType.fromBackendValue('jumping-jacks'),
      MotionActivityType.jumpingJacks,
    );

    final jacks = liveProofActivityForId('jumping_jacks');

    expect(jacks, isNotNull);
    expect(jacks!.activityId, 'jumping_jacks');
    expect(jacks.title, 'Jumping Jacks');
  });
}
