import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/local_motion_signature.dart';
import 'package:nuvo/features/races/ai/live_proof_models.dart';
import 'package:nuvo/features/races/ai/universal_live_proof_validator.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';

void main() {
  LiveProofActivityDefinition makeActivity({int target = 2}) {
    return universalLiveProofActivityDefinition(
      activityId: 'basketball_shots',
      title: 'Basketball shots',
      metric: RaceMetric.reps,
      unit: 'shots',
      defaultTarget: target,
      proofPrompt:
          'Count one when the person releases a basketball shot toward the hoop.',
    );
  }

  LiveProofActivityDefinition makeLocalActivity({
    required LocalMotionSignature signature,
    int target = 2,
  }) {
    return universalLiveProofActivityDefinition(
      activityId: 'custom_motion',
      title: 'Custom motion',
      metric: RaceMetric.reps,
      unit: 'motions',
      defaultTarget: target,
      proofPrompt: 'Use local motion signature.',
      minimumConfidence: 0.62,
      motionSignature: signature,
    );
  }

  NuvoPoseFrame poseFrame(double progress) {
    const names = [
      'leftShoulder',
      'rightShoulder',
      'leftElbow',
      'rightElbow',
      'leftWrist',
      'rightWrist',
      'leftHip',
      'rightHip',
    ];
    return NuvoPoseFrame(
      points: {
        for (var i = 0; i < names.length; i++)
          names[i]: NuvoPosePoint(
            x: 0.28 + (i * 0.04),
            y: 0.72 - (progress * 0.28),
            z: 0,
            likelihood: 0.95,
          ),
      },
      imageWidth: 720,
      imageHeight: 1280,
      createdAt: DateTime(
        2026,
        1,
        1,
      ).add(Duration(milliseconds: (progress * 1000).round())),
    );
  }

  CloudflareVisionLiveProofSignal signal({
    required String id,
    bool detected = true,
    bool complete = true,
    double confidence = 0.91,
    String summary = 'That counts.',
  }) {
    return CloudflareVisionLiveProofSignal(
      observationId: id,
      prompt: 'Count clean basketball shots.',
      activityDetected: detected,
      actionComplete: complete,
      confidence: confidence,
      summary: summary,
    );
  }

  test(
    'universal validator counts completed Cloudflare vision observations',
    () {
      final activity = makeActivity();
      final validator = activity.createValidator(
        LiveProofValidatorConfig(
          activityId: activity.activityId,
          targetValue: 2,
          metric: activity.metric,
          unit: activity.unit,
          validatorVersion: activity.validatorVersion,
          minimumConfidence: activity.minimumConfidence,
        ),
      );

      validator.start();
      final first = validator.update(
        LiveProofSignalBatch(signals: [signal(id: 'frame-1')]),
      );
      final second = validator.update(
        LiveProofSignalBatch(signals: [signal(id: 'frame-2')]),
      );
      final result = validator.finish();

      expect(first.currentValue, 1);
      expect(second.currentValue, 2);
      expect(second.status, LiveProofStatus.targetComplete);
      expect(result.isVerified, isTrue);
      expect(result.value, 2);
      expect(result.metadata['proofPrompt'], contains('basketball'));
    },
  );

  test('universal validator ignores duplicate observation ids', () {
    final activity = makeActivity();
    final validator = activity.createValidator(
      LiveProofValidatorConfig(
        activityId: activity.activityId,
        targetValue: 2,
        metric: activity.metric,
        unit: activity.unit,
        validatorVersion: activity.validatorVersion,
        minimumConfidence: activity.minimumConfidence,
      ),
    );

    validator.start();
    validator.update(LiveProofSignalBatch(signals: [signal(id: 'frame-1')]));
    validator.update(LiveProofSignalBatch(signals: [signal(id: 'frame-1')]));
    final result = validator.finish();

    expect(validator.currentValue, 1);
    expect(result.isVerified, isFalse);
  });

  test('universal validator requires visibility and confidence', () {
    final activity = makeActivity(target: 1);
    final validator = activity.createValidator(
      LiveProofValidatorConfig(
        activityId: activity.activityId,
        targetValue: 1,
        metric: activity.metric,
        unit: activity.unit,
        validatorVersion: activity.validatorVersion,
        minimumConfidence: activity.minimumConfidence,
      ),
    );

    validator.start();
    final invisible = validator.update(
      LiveProofSignalBatch(signals: [signal(id: 'frame-1', detected: false)]),
    );
    final lowConfidence = validator.update(
      LiveProofSignalBatch(signals: [signal(id: 'frame-2', confidence: 0.3)]),
    );
    final result = validator.finish();

    expect(invisible.failedRuleReason, 'activity_not_visible');
    expect(lowConfidence.failedRuleReason, 'low_confidence');
    expect(result.isVerified, isFalse);
    expect(result.value, 0);
  });

  test('universal validator counts local motion signature after reset', () {
    final signature = LocalMotionSignature.fromFrames(
      actionName: 'custom motion',
      cleanFrames: [
        poseFrame(0),
        poseFrame(0.15),
        poseFrame(0.35),
        poseFrame(0.65),
        poseFrame(0.85),
        poseFrame(1),
      ],
      rejectFrames: [poseFrame(0), poseFrame(0.2), poseFrame(0.35)],
    );
    final activity = makeLocalActivity(signature: signature);
    final validator = activity.createValidator(
      LiveProofValidatorConfig(
        activityId: activity.activityId,
        targetValue: 2,
        metric: activity.metric,
        unit: activity.unit,
        validatorVersion: activity.validatorVersion,
        minimumConfidence: activity.minimumConfidence,
      ),
    );

    validator.start();
    validator.update(
      LiveProofSignalBatch(signals: [PoseLiveProofSignal(frame: poseFrame(0))]),
    );
    final first = validator.update(
      LiveProofSignalBatch(
        signals: [PoseLiveProofSignal(frame: poseFrame(0.95))],
      ),
    );
    final heldEnd = validator.update(
      LiveProofSignalBatch(signals: [PoseLiveProofSignal(frame: poseFrame(1))]),
    );
    validator.update(
      LiveProofSignalBatch(signals: [PoseLiveProofSignal(frame: poseFrame(0))]),
    );
    final second = validator.update(
      LiveProofSignalBatch(
        signals: [PoseLiveProofSignal(frame: poseFrame(0.95))],
      ),
    );
    final result = validator.finish();

    expect(first.currentValue, 1);
    expect(heldEnd.currentValue, 1);
    expect(second.currentValue, 2);
    expect(second.status, LiveProofStatus.targetComplete);
    expect(result.isVerified, isTrue);
    expect(result.metadata['requiredSignal'], LiveProofSignalType.pose.name);
  });
}
