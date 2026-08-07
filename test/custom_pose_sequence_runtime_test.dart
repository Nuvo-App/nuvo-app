import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_sequence_builder.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_sequence_runtime.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/features/races/ai/custom_pose/normalized_pose.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_models.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_quality.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_sequence_frame.dart';
import 'package:nuvo/features/races/ai/verifier_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';

import 'fixtures/pose_fixtures.dart';

void main() {
  group('construction', () {
    test('valid custom spec creates runtime through Stage 1 boundary', () {
      final spec = _terminalSpec();
      final eligibility = resolveCameraVerification(_race());
      final resolution = const VerifierRuntimeResolver().resolve(
        eligibility: eligibility,
        explicitVerifierType: customPoseVerifierType,
      );

      final runtime = resolution.createRuntime(target: 5, customSpec: spec);

      expect(runtime.type, VerifierType.customPoseSequence);
      expect(runtime.targetValue, 5);
    });

    test('missing, invalid, and unsupported custom specs fail clearly', () {
      final eligibility = resolveCameraVerification(_race());
      final resolution = const VerifierRuntimeResolver().resolve(
        eligibility: eligibility,
        explicitVerifierType: customPoseVerifierType,
      );
      final spec = _terminalSpec();

      expect(
        () => resolution.createRuntime(target: 5),
        throwsA(isA<VerifierRuntimeException>()),
      );
      expect(
        () => resolution.createRuntime(
          target: 5,
          customSpec: CustomPoseVerifierSpec(
            schemaVersion: 99,
            verifierType: spec.verifierType,
            movementName: spec.movementName,
            measurementType: spec.measurementType,
            startPose: spec.startPose,
            completionPose: spec.completionPose,
            completionStrategy: spec.completionStrategy,
            canonicalSequence: spec.canonicalSequence,
            requiredFeatureIds: spec.requiredFeatureIds,
            activeFeatureIds: spec.activeFeatureIds,
            sequenceSimilarityThreshold: spec.sequenceSimilarityThreshold,
            completionSimilarityThreshold: spec.completionSimilarityThreshold,
            resetSimilarityThreshold: spec.resetSimilarityThreshold,
            minimumValidFeatureRatio: spec.minimumValidFeatureRatio,
            minimumVisibility: spec.minimumVisibility,
            cooldownMs: spec.cooldownMs,
            expectedSequenceFrameCount: spec.expectedSequenceFrameCount,
            calibrationSummary: spec.calibrationSummary,
          ),
        ),
        throwsA(isA<VerifierRuntimeException>()),
      );
      expect(
        () => CustomPoseSequenceRuntime(
          spec: CustomPoseVerifierSpec(
            schemaVersion: spec.schemaVersion,
            verifierType: spec.verifierType,
            movementName: spec.movementName,
            measurementType: spec.measurementType,
            startPose: spec.startPose,
            completionPose: spec.completionPose,
            completionStrategy: spec.completionStrategy,
            canonicalSequence: spec.canonicalSequence,
            requiredFeatureIds: const [],
            activeFeatureIds: const [],
            sequenceSimilarityThreshold: spec.sequenceSimilarityThreshold,
            completionSimilarityThreshold: spec.completionSimilarityThreshold,
            resetSimilarityThreshold: spec.resetSimilarityThreshold,
            minimumValidFeatureRatio: spec.minimumValidFeatureRatio,
            minimumVisibility: spec.minimumVisibility,
            cooldownMs: spec.cooldownMs,
            expectedSequenceFrameCount: spec.expectedSequenceFrameCount,
            calibrationSummary: spec.calibrationSummary,
          ),
        )..start(),
        returnsNormally,
      );
    });

    test('preset runtime behavior remains unchanged', () {
      final eligibility = resolveCameraVerification(_race());
      final runtime = const VerifierRuntimeResolver()
          .resolve(eligibility: eligibility)
          .createRuntime(target: 15);

      expect(runtime.type, VerifierType.presetPose);
      expect(runtime.targetValue, 15);
      expect(
        runtime.finish().aiMotionResult!.activity,
        AiMotionActivity.pushUps,
      );
    });
  });

  group('start arming', () {
    test('one matching frame does not arm but stable start frames do', () {
      final runtime = _runtime(_terminalSpec())..start();

      var update = runtime.update(_neutral()).customPoseUpdate!;
      expect(update.state, isNot(CustomPoseRuntimeState.armed));
      expect(update.frameNoAdvanceReason, 'holding_start_pose');
      expect(update.requiredFeatureRatio, greaterThan(0));

      update = runtime.update(_neutral()).customPoseUpdate!;
      update = runtime.update(_neutral()).customPoseUpdate!;
      expect(update.state, CustomPoseRuntimeState.armed);
      expect(update.frameAdvancedVerification, isTrue);
    });

    test('low feature coverage and halfway starts do not arm', () {
      final runtime = _runtime(_terminalSpec())..start();

      for (var i = 0; i < 4; i++) {
        runtime.update(
          neutralStandingPose(
            missing: {'leftHip', 'rightHip', 'leftShoulder', 'rightShoulder'},
          ),
        );
      }
      expect(runtime.lastUpdate.state, CustomPoseRuntimeState.waitingForStart);
      expect(
        runtime.lastUpdate.frameNoAdvanceReason,
        anyOf('missing_required_features', 'missing_origin_landmarks'),
      );
      expect(runtime.lastUpdate.requiredFeatureRatio, 0);

      final halfway = _runtime(_terminalSpec())..start();
      for (var i = 0; i < 5; i++) {
        halfway.update(_overhead());
      }
      expect(halfway.lastUpdate.state, CustomPoseRuntimeState.waitingForStart);
      expect(halfway.currentValue, 0);
      expect(
        halfway.lastUpdate.frameNoAdvanceReason,
        'start_similarity_below_threshold',
      );
    });
  });

  group('complete sequence', () {
    test('exact, noisy, faster, slower, and held sequences count', () {
      for (final frames in [
        _terminalAttempt(),
        _terminalAttempt(dx: 0.01),
        _terminalAttempt(fast: true),
        _terminalAttempt(slow: true),
        _terminalAttempt(holdMiddle: true),
      ]) {
        final runtime = _runtime(_terminalSpec())..start();
        _play(runtime, frames);

        expect(
          runtime.currentValue,
          1,
          reason:
              '${runtime.lastUpdate.state} progress=${runtime.lastUpdate.sequenceProgress} '
              'sim=${runtime.lastUpdate.currentSimilarity} completion=${runtime.lastUpdate.completionSimilarity} '
              'reset=${runtime.lastUpdate.resetSimilarity} failure=${runtime.failedRuleReason}',
        );
      }
    });

    test('multiple correct repetitions count correctly', () {
      final runtime = _runtime(_terminalSpec())..start();

      for (var i = 0; i < 3; i++) {
        _play(runtime, _terminalAttempt());
      }

      expect(runtime.currentValue, 3);
    });
  });

  group('partial and invalid sequences', () {
    test(
      'partial, reversed, out-of-order, and final-only movements do not count',
      () {
        for (final frames in [
          _partialAttempt(),
          _reversedAttempt(),
          _outOfOrderAttempt(),
          _finalOnlyAttempt(),
        ]) {
          final runtime = _runtime(_terminalSpec())..start();
          _play(runtime, frames);

          expect(runtime.currentValue, 0);
        }
      },
    );

    test('left and right mirror mismatch can still match learned wave', () {
      final runtime = _runtime(_leftArmSpec())..start();

      _play(runtime, [
        _neutral(),
        _neutral(),
        _neutral(),
        rightArmRaisedPose(),
        rightArmRaisedPose(),
        rightArmRaisedPose(),
        rightArmRaisedPose(),
      ]);

      expect(
        runtime.currentValue,
        1,
        reason:
            '${runtime.lastUpdate.state} progress=${runtime.lastUpdate.sequenceProgress} '
            'sim=${runtime.lastUpdate.currentSimilarity} completion=${runtime.lastUpdate.completionSimilarity} '
            'reset=${runtime.lastUpdate.resetSimilarity} failure=${runtime.failedRuleReason}',
      );
      expect(runtime.lastUpdate.mirroredComparisonUsed, isTrue);
    });
  });

  group('completion, reset, cooldown, and return strategy', () {
    test('terminal completion counts once and requires reset', () {
      final runtime = _runtime(_terminalSpec())..start();

      _play(runtime, [
        ..._terminalAttempt(includeReset: false),
        _overhead(),
        _overhead(),
        _overhead(),
        _overhead(),
      ]);
      expect(runtime.currentValue, 1);

      _play(runtime, [_overhead(), _overhead(), _overhead()]);
      expect(runtime.currentValue, 1);

      _play(runtime, [
        _neutral(),
        _neutral(),
        _neutral(),
        ..._terminalAttempt(),
      ]);
      expect(runtime.currentValue, 2);
    });

    test('return-to-start completion counts only after validated return', () {
      final runtime = _runtime(_returnSpec())..start();

      _play(runtime, _terminalAttempt(includeReset: false));
      expect(runtime.currentValue, 0);

      _play(runtime, [for (var i = 0; i < 8; i++) _neutral()]);
      expect(
        runtime.currentValue,
        1,
        reason:
            '${runtime.lastUpdate.state} progress=${runtime.lastUpdate.sequenceProgress} '
            'idx=${runtime.lastUpdate.currentTemplateIndex} sim=${runtime.lastUpdate.currentSimilarity} '
            'reset=${runtime.lastUpdate.resetSimilarity} failure=${runtime.failedRuleReason}',
      );

      _play(runtime, [_neutral(), _neutral(), _neutral(), _neutral()]);
      expect(runtime.currentValue, 1);

      _play(runtime, _terminalAttempt());
      expect(runtime.currentValue, 2);
    });
  });

  group('timeout and missing landmarks', () {
    test('stalled partial attempt times out and preserves previous count', () {
      final runtime = _runtime(_terminalSpec())..start();
      _play(runtime, _terminalAttempt());
      expect(runtime.currentValue, 1);

      _play(runtime, [_neutral(), _neutral(), _neutral(), _overhead()]);
      for (var i = 0; i < customPoseProgressTimeoutFrames + 2; i++) {
        runtime.update(_overhead());
      }

      expect(runtime.currentValue, 1);
      expect(runtime.failedRuleReason, 'progress_timeout');

      _play(runtime, [
        _neutral(),
        _neutral(),
        _neutral(),
        ..._terminalAttempt(),
      ]);
      expect(runtime.currentValue, 2);
    });

    test(
      'brief missing feature window pauses but extended loss invalidates attempt',
      () {
        final runtime = _runtime(_terminalSpec())..start();
        _play(runtime, [_neutral(), _neutral(), _neutral(), _overhead()]);
        final progressBefore = runtime.lastUpdate.sequenceProgress;

        for (var i = 0; i < customPoseMissingFeatureGraceFrames; i++) {
          runtime.update(
            neutralStandingPose(
              missing: {'leftHip', 'rightHip', 'leftShoulder', 'rightShoulder'},
            ),
          );
        }
        expect(runtime.lastUpdate.sequenceProgress, progressBefore);
        expect(runtime.currentValue, 0);
        expect(
          runtime.lastUpdate.frameNoAdvanceReason,
          'missing_origin_landmarks',
        );

        runtime.update(
          neutralStandingPose(
            missing: {'leftHip', 'rightHip', 'leftShoulder', 'rightShoulder'},
          ),
        );
        expect(runtime.failedRuleReason, 'missing_required_features');
        expect(
          runtime.lastUpdate.frameNoAdvanceReason,
          anyOf('missing_required_features', 'missing_origin_landmarks'),
        );
      },
    );
  });

  test('learned arm movement does not require face landmarks', () {
    final spec = _leftArmSpec();
    expect(spec.requiredFeatureIds.where(_isFaceOrHeadFeature), isEmpty);
    final runtime = _runtime(spec)..start();

    _play(runtime, [
      _withoutFace(_neutral()),
      _withoutFace(_neutral()),
      _withoutFace(_neutral()),
      _withoutFace(leftArmRaisedPose()),
      _withoutFace(leftArmRaisedPose()),
      _withoutFace(leftArmRaisedPose()),
      _withoutFace(leftArmRaisedPose()),
    ]);

    expect(
      runtime.currentValue,
      1,
      reason:
          '${runtime.lastUpdate.state} progress=${runtime.lastUpdate.sequenceProgress} '
          'sim=${runtime.lastUpdate.currentSimilarity} completion=${runtime.lastUpdate.completionSimilarity} '
          'reset=${runtime.lastUpdate.resetSimilarity} failure=${runtime.failedRuleReason}',
    );
  });

  group('runtime result', () {
    test('five repetitions produce successful serializable result', () {
      final runtime = _runtime(_terminalSpec())..start();

      for (var i = 0; i < 5; i++) {
        _play(runtime, _terminalAttempt());
      }
      final result = runtime.customResult();
      final decoded = CustomPoseRuntimeResult.fromJson(
        jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>,
      );

      expect(result.isVerified, isTrue);
      expect(result.count, 5);
      expect(result.confidence.isFinite, isTrue);
      expect(result.framesAnalyzed, greaterThan(0));
      expect(result.validFrames, greaterThan(0));
      expect(result.durationMs, isNonNegative);
      expect(decoded.count, result.count);
      expect(decoded.verifierType, customPoseVerifierType);
    });

    test('incomplete target produces non-success result', () {
      final runtime = _runtime(_terminalSpec())..start();
      _play(runtime, _terminalAttempt());

      final result = runtime.customResult();

      expect(result.isVerified, isFalse);
      expect(result.finalFailureReason, 'target_not_met');
    });
  });

  group('mismatched movement', () {
    test('single-side raise does not count as overhead movement', () {
      final runtime = _runtime(_terminalSpec())..start();

      _play(runtime, [
        _neutral(),
        _neutral(),
        _neutral(),
        leftArmRaisedPose(),
        leftArmRaisedPose(),
        leftArmRaisedPose(),
      ]);

      expect(runtime.currentValue, 0);
    });
  });
}

CustomPoseSequenceRuntime _runtime(CustomPoseVerifierSpec spec) {
  return CustomPoseSequenceRuntime(spec: spec, target: 5);
}

CustomPoseVerifierSpec _terminalSpec() {
  return _buildSpec([
    _demo(1, _terminalPoses()),
    _demo(2, _terminalPoses(dx: 0.01)),
    _demo(3, _terminalPoses(dx: -0.01)),
  ]);
}

CustomPoseVerifierSpec _returnSpec() {
  return _buildSpec([
    _demo(1, _returnPoses()),
    _demo(2, _returnPoses(dx: 0.01)),
    _demo(3, _returnPoses(dx: -0.01)),
  ]);
}

CustomPoseVerifierSpec _leftArmSpec() {
  return _buildSpec([
    _demo(1, _leftArmPoses()),
    _demo(2, _leftArmPoses(dx: 0.01)),
    _demo(3, _leftArmPoses(dx: -0.01)),
  ]);
}

CustomPoseVerifierSpec _buildSpec(List<PoseDemonstration> demos) {
  final start = const PoseNormalizer().normalize(neutralStandingPose());
  final calibration = CustomPoseCalibration(
    schemaVersion: poseCalibrationSchemaVersion,
    movementName: 'Learned move',
    startPose: start,
    demonstrations: demos,
    quality: evaluateCalibrationQuality(
      startPose: start,
      startPoseStability: 1,
      demonstrations: demos,
    ),
    metadata: const CalibrationCaptureMetadata(
      capturedAtIso8601: '2026-01-01T00:00:00.000Z',
      cameraLensDirection: 'back',
      orientation: 'portraitUp',
      normalizerVersion: 'stage2-v1',
      deviceNote: 'test',
    ),
  );
  final result = const CustomPoseSequenceBuilder().build(calibration);
  expect(result.succeeded, isTrue, reason: result.failureReason);
  return result.spec!;
}

PoseDemonstration _demo(int index, List<NormalizedPose> poses) {
  return PoseDemonstration(
    index: index,
    frames: _frames(poses),
    durationMs: 1200,
    processedFrameCount: poses.length,
    validFrameCount: poses.length,
    validFrameRatio: 1,
    averageVisibility: 1,
    accepted: true,
  );
}

List<PoseSequenceFrame> _frames(List<NormalizedPose> poses) {
  return List.generate(poses.length, (index) {
    return PoseSequenceFrame(
      schemaVersion: normalizedPoseSchemaVersion,
      position: poses.length == 1 ? 0 : index / (poses.length - 1),
      elapsedMs: index * 120,
      pose: poses[index],
    );
  }, growable: false);
}

List<NormalizedPose> _terminalPoses({double dx = 0}) {
  const normalizer = PoseNormalizer();
  return [
    normalizer.normalize(neutralStandingPose(dx: dx)),
    normalizer.normalize(leftArmRaisedPose(dx: dx)),
    normalizer.normalize(armsOverheadPose(dx: dx)),
    normalizer.normalize(armsOverheadPose(dx: dx)),
  ];
}

List<NormalizedPose> _returnPoses({double dx = 0}) {
  const normalizer = PoseNormalizer();
  return [
    normalizer.normalize(neutralStandingPose(dx: dx)),
    normalizer.normalize(leftArmRaisedPose(dx: dx)),
    normalizer.normalize(armsOverheadPose(dx: dx)),
    normalizer.normalize(armsOverheadPose(dx: dx)),
    normalizer.normalize(neutralStandingPose(dx: dx)),
    normalizer.normalize(neutralStandingPose(dx: dx)),
  ];
}

List<NormalizedPose> _leftArmPoses({double dx = 0}) {
  const normalizer = PoseNormalizer();
  return [
    normalizer.normalize(neutralStandingPose(dx: dx)),
    normalizer.normalize(leftArmRaisedPose(dx: dx)),
    normalizer.normalize(leftArmRaisedPose(dx: dx)),
    normalizer.normalize(leftArmRaisedPose(dx: dx)),
  ];
}

List<NuvoPoseFrame> _terminalAttempt({
  double dx = 0,
  bool fast = false,
  bool slow = false,
  bool holdMiddle = false,
  bool includeReset = true,
}) {
  final frames = <NuvoPoseFrame>[
    _neutral(dx: dx),
    _neutral(dx: dx),
    _neutral(dx: dx),
    _blend(_neutral(dx: dx), leftArmRaisedPose(dx: dx), 0.25),
    _blend(_neutral(dx: dx), leftArmRaisedPose(dx: dx), 0.50),
    _blend(_neutral(dx: dx), leftArmRaisedPose(dx: dx), 0.75),
    leftArmRaisedPose(dx: dx),
    _blend(leftArmRaisedPose(dx: dx), _overhead(dx: dx), 0.25),
    _blend(leftArmRaisedPose(dx: dx), _overhead(dx: dx), 0.50),
    _blend(leftArmRaisedPose(dx: dx), _overhead(dx: dx), 0.75),
    _overhead(dx: dx),
    _overhead(dx: dx),
    _overhead(dx: dx),
    _overhead(dx: dx),
  ];
  if (holdMiddle) {
    frames.insertAll(4, [leftArmRaisedPose(dx: dx), leftArmRaisedPose(dx: dx)]);
  }
  if (slow) {
    frames.insertAll(3, [_neutral(dx: dx), leftArmRaisedPose(dx: dx)]);
    frames.add(_overhead(dx: dx));
  }
  if (fast) {
    frames.removeAt(3);
  }
  if (includeReset) {
    frames.addAll([for (var i = 0; i < 10; i++) _neutral(dx: dx)]);
  }
  return frames;
}

List<NuvoPoseFrame> _partialAttempt() => [
  _neutral(),
  _neutral(),
  _neutral(),
  _blend(_neutral(), leftArmRaisedPose(), 0.25),
  _blend(_neutral(), leftArmRaisedPose(), 0.50),
];

List<NuvoPoseFrame> _reversedAttempt() => [
  _neutral(),
  _neutral(),
  _neutral(),
  _overhead(),
  _blend(leftArmRaisedPose(), _overhead(), 0.50),
  _neutral(),
];

List<NuvoPoseFrame> _outOfOrderAttempt() => [
  _neutral(),
  _neutral(),
  _neutral(),
  _overhead(),
  _neutral(),
  _blend(_neutral(), leftArmRaisedPose(), 0.50),
];

List<NuvoPoseFrame> _finalOnlyAttempt() => [
  _neutral(),
  _neutral(),
  _neutral(),
  _overhead(),
  _overhead(),
  _overhead(),
];

void _play(CustomPoseSequenceRuntime runtime, List<NuvoPoseFrame> frames) {
  for (final frame in frames) {
    runtime.update(frame);
  }
}

NuvoPoseFrame _withoutFace(NuvoPoseFrame frame) {
  final points = Map<String, NuvoPosePoint>.of(frame.points)
    ..removeWhere(_isFaceOrHeadLandmark);
  return NuvoPoseFrame(
    points: Map.unmodifiable(points),
    imageWidth: frame.imageWidth,
    imageHeight: frame.imageHeight,
    createdAt: frame.createdAt,
  );
}

bool _isFaceOrHeadLandmark(String id, NuvoPosePoint _) =>
    id == 'nose' ||
    id.contains('Eye') ||
    id.contains('Ear') ||
    id.contains('Mouth');

bool _isFaceOrHeadFeature(String featureId) {
  return poseFeatureBodyPart(featureId) == 'face/head';
}

NuvoPoseFrame _neutral({double dx = 0}) => neutralStandingPose(dx: dx);

NuvoPoseFrame _overhead({double dx = 0}) => armsOverheadPose(dx: dx);

NuvoPoseFrame _blend(NuvoPoseFrame from, NuvoPoseFrame to, double t) {
  final points = <String, NuvoPosePoint>{};
  for (final id in from.points.keys) {
    final a = from.points[id];
    final b = to.points[id];
    if (a == null || b == null) continue;
    points[id] = NuvoPosePoint(
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      z: a.z + (b.z - a.z) * t,
      likelihood: a.likelihood + (b.likelihood - a.likelihood) * t,
    );
  }
  return NuvoPoseFrame(
    points: points,
    imageWidth: from.imageWidth,
    imageHeight: from.imageHeight,
    createdAt: from.createdAt.add(Duration(milliseconds: (120 * t).round())),
  );
}

Race _race() {
  return const Race(
    id: 'race-1',
    creatorId: 'user-1',
    title: 'First to 15 Pushups',
    goalType: 'first_to_goal',
    targetValue: 15,
    unit: 'reps',
    aiActivityType: null,
    targetUnit: 'reps',
    activityId: 'push_ups',
    metric: 'reps',
    format: 'first_to_goal',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: 'active',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  );
}
