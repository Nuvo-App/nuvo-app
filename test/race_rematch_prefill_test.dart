import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';

Race _race({
  String title = 'Best reach taps attempt',
  String? activityId,
  String format = 'best_attempt',
  int? targetValue,
  String? metric = 'reps',
  String? finishLineAt,
  int? attemptDurationSeconds,
  String verifierType = 'preset_pose',
  String? customActivityName,
}) {
  return Race(
    id: 'race-remote',
    creatorId: 'user-1',
    title: title,
    goalType: format,
    targetValue: targetValue,
    unit: metric,
    activityId: activityId,
    metric: metric,
    format: format,
    attemptDurationSeconds: attemptDurationSeconds,
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    verifierType: verifierType,
    customActivityName: customActivityName,
    finishLineAt: finishLineAt,
    status: 'active',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  );
}

void main() {
  group('prefillFromRace rematch/clone', () {
    test('test_gap10_prefill_preserves_remote_activity_and_format', () {
      // A registry-published motion this build never compiled: rematch must
      // keep the real activityId and the stored format — never degrade to
      // Pushups + First to.
      final remote = _race(
        activityId: 'reach_taps',
        format: 'best_attempt',
        finishLineAt: '2026-02-01T00:00:00Z',
      );
      final remoteDraft = prefillFromRace(remote).draft!;
      expect(remoteDraft.activity.activityId, 'reach_taps');
      expect(remoteDraft.activity.type, MotionActivityType.remote);
      expect(remoteDraft.format, RaceFormat.bestAttempt);
      expect(remoteDraft.finishLineAt, '2026-02-01T00:00:00Z');
      // The create payload carries the same identity back to the server.
      final payload = remoteDraft.toCreatePayload();
      expect(payload['activityId'], 'reach_taps');
      expect(payload['aiActivityType'], 'reach_taps');
      expect(payload['format'], 'best_attempt');

      // When the live catalog resolves the ID, its real formats apply and
      // the stored format still survives the prefill.
      const catalogDef = MotionActivityDefinition(
        type: MotionActivityType.remote,
        backendId: 'reach_taps',
        title: 'Reach Taps',
        metric: RaceMetric.reps,
        suggestedTargets: [30],
        supportedFormats: [
          RaceFormat.firstToGoal,
          RaceFormat.mostInWindow,
          RaceFormat.bestAttempt,
          RaceFormat.timedAttempt,
        ],
        aliases: [],
        proofLabel: 'Reach Taps',
        cameraInstruction: 'Reach.',
        instructions: ['Reach.'],
        icon: Icons.fitness_center_rounded,
        framingLabel: '',
        preferredCameraView: PreferredCameraView.frontPreferred,
        category: MovementCategory.fullBody,
      );
      final viaCatalog = prefillFromRace(remote, catalog: [catalogDef]).draft!;
      expect(viaCatalog.activity.activityId, 'reach_taps');
      expect(viaCatalog.activity.title, 'Reach Taps');
      expect(viaCatalog.format, RaceFormat.bestAttempt);

      // A timed battle keeps its attempt duration too.
      final timed = _race(
        activityId: 'reach_taps',
        format: 'timed_attempt',
        attemptDurationSeconds: 90,
        finishLineAt: '2026-02-01T00:00:00Z',
      );
      final timedDraft = prefillFromRace(timed).draft!;
      expect(timedDraft.format, RaceFormat.timedAttempt);
      expect(timedDraft.attemptDurationSeconds, 90);

      // A taught custom movement races again as itself.
      final custom = _race(
        activityId: null,
        format: 'first_to_goal',
        targetValue: 12,
        verifierType: 'motion_v2',
        customActivityName: 'Knee Touch',
      );
      final customDraft = prefillFromRace(custom).draft!;
      expect(customDraft.isCustom, isTrue);
      expect(customDraft.customActivityName, 'Knee Touch');
      expect(customDraft.format, RaceFormat.firstToGoal);
      expect(customDraft.targetValue, 12);
      expect(customDraft.activity.type, isNot(MotionActivityType.pushUps));
    });
  });
}
