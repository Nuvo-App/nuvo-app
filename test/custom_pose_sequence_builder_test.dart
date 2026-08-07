import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_sequence_builder.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/features/races/ai/custom_pose/normalized_pose.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_models.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_quality.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_sequence_frame.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_similarity.dart';

import 'fixtures/pose_fixtures.dart';

void main() {
  const builder = CustomPoseSequenceBuilder();

  group('CustomPoseSequenceBuilder validation', () {
    test('ready calibration builds a valid verifier spec', () {
      final result = builder.build(_calibration());

      expect(result.succeeded, isTrue);
      final spec = result.spec!;
      expect(spec.verifierType, customPoseVerifierType);
      expect(spec.measurementType, customPoseMeasurementType);
      expect(spec.schemaVersion, customPoseVerifierSpecSchemaVersion);
      expect(spec.canonicalSequence, hasLength(customPoseTemplateFrameCount));
      expect(spec.activeFeatureIds, isNotEmpty);
      expect(spec.requiredFeatureIds, isNotEmpty);
      expect(
        spec.requiredFeatureIds.every(spec.activeFeatureIds.contains),
        isTrue,
      );
      expect(spec.canonicalSequence.first.position, 0);
      expect(spec.canonicalSequence.last.position, 1);
      expect(() => spec.validate(), returnsNormally);
    });

    test('not-ready calibration is rejected', () {
      final result = builder.build(
        _calibration(
          quality: const CalibrationQuality(
            startPoseValid: true,
            startPoseStability: 1,
            startPoseCoverage: 1,
            demonstrationCount: 3,
            averageValidFrameRatio: 1,
            averagePoseCoverage: 1,
            interrupted: true,
            readyForBuilder: false,
            reasons: ['capture_interrupted'],
          ),
        ),
      );

      expect(result.succeeded, isFalse);
      expect(result.failureReason, 'calibration_not_ready');
    });

    test('wrong demonstration count and empty demonstrations are rejected', () {
      expect(
        builder.build(_calibration(demos: [_demo(1), _demo(2)])).failureReason,
        'calibration_not_ready',
      );
      expect(
        builder
            .build(
              _calibration(
                demos: [
                  _demo(1),
                  _demo(2),
                  _demo(3, poses: const []),
                ],
              ),
            )
            .failureReason,
        'demo_3_empty',
      );
    });

    test('invalid start pose and malformed nested JSON are rejected', () {
      const start = NormalizedPose(
        schemaVersion: normalizedPoseSchemaVersion,
        landmarks: {},
        features: PoseFeatureVector({}),
        originX: 0,
        originY: 0,
        scale: 1,
        originReference: 'none',
        scaleReference: 'none',
        validLandmarkCount: 0,
        validFeatureCount: 0,
        invalidReason: 'test_invalid',
      );

      expect(
        builder.build(_calibration(startPose: start)).failureReason,
        'calibration_not_ready',
      );

      final json = _calibration().toJson();
      expect(
        () => CustomPoseCalibration.fromJson({
          ...json,
          'demonstrations': [
            {
              ...((json['demonstrations'] as List).first
                  as Map<String, dynamic>),
              'frames': [
                {'bad': 'frame'},
              ],
            },
          ],
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
    });
  });

  group('Static trimming and completion strategy', () {
    test('leading and trailing start padding are reduced', () {
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _returnToStartPoses(leading: 3, trailing: 4)),
            _demo(2, poses: _returnToStartPoses(leading: 2, trailing: 3)),
            _demo(3, poses: _returnToStartPoses(leading: 4, trailing: 2)),
          ],
        ),
      );

      expect(result.succeeded, isTrue);
      final spec = result.spec!;
      expect(
        spec.completionStrategy,
        CustomPoseCompletionStrategy.completionAfterSequenceReturn,
      );
      expect(spec.canonicalSequence, hasLength(customPoseTemplateFrameCount));
      expect(spec.activeFeatureIds.any((id) => id.contains('Wrist')), isTrue);
    });

    test('entirely static demonstration is rejected', () {
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _staticPoses()),
            _demo(2, poses: _returnToStartPoses()),
            _demo(3, poses: _returnToStartPoses()),
          ],
        ),
      );

      expect(result.succeeded, isFalse);
      expect(result.failureReason, contains('static_capture'));
    });

    test('terminal completion is not replaced by reset frames', () {
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _terminalPoses()),
            _demo(2, poses: _terminalPoses(dx: 0.01)),
            _demo(3, poses: _terminalPoses(dx: -0.01)),
          ],
        ),
      );

      expect(result.succeeded, isTrue);
      final spec = result.spec!;
      expect(
        spec.completionStrategy,
        CustomPoseCompletionStrategy.completionAtTerminalPose,
      );
      final similarity = const PoseSimilarity().compare(
        spec.startPose,
        spec.completionPose,
      );
      expect(similarity.similarity, lessThan(spec.resetSimilarityThreshold));
    });
  });

  group('Resampling, active features, and consistency', () {
    test(
      'short and long demonstrations produce equal deterministic templates',
      () {
        final calibration = _calibration(
          demos: [
            _demo(1, poses: _returnToStartPoses(leading: 1, trailing: 1)),
            _demo(2, poses: _returnToStartPoses(leading: 3, trailing: 2)),
            _demo(3, poses: _returnToStartPoses(leading: 2, trailing: 4)),
          ],
        );

        final first = builder.build(calibration).spec!;
        final second = builder.build(calibration).spec!;

        expect(
          first.canonicalSequence,
          hasLength(customPoseTemplateFrameCount),
        );
        expect(
          first.canonicalSequence.map((frame) => frame.position),
          orderedEquals(
            second.canonicalSequence.map((frame) => frame.position),
          ),
        );
        expect(first.toDeterministicJson(), second.toDeterministicJson());
        for (final frame in first.canonicalSequence) {
          expect(frame.position.isFinite, isTrue);
          expect(
            frame.features.values.every((value) => value.value.isFinite),
            isTrue,
          );
        }
      },
    );

    test('moving features are selected while static features are excluded', () {
      final result = builder.build(_calibration());

      expect(result.succeeded, isTrue);
      final active = result.spec!.activeFeatureIds;
      expect(active, contains('landmark.leftWrist.y'));
      expect(active, contains('landmark.rightWrist.y'));
      expect(active, isNot(contains('distance.foot_separation')));
      expect(
        result.featureDiagnostics
            .where((item) => item.rejectionReason == 'not_moving_enough')
            .map((item) => item.featureId),
        contains('distance.foot_separation'),
      );
      final diagnostics = result.toDiagnosticsJson();
      expect(diagnostics['activeFeatures'], isNotEmpty);
      expect(
        (diagnostics['activeFeatures'] as List)
            .map((item) => item as Map<String, dynamic>)
            .map((item) => item['featureId']),
        contains('landmark.leftWrist.y'),
      );
    });

    test('two short wave demonstrations build a valid verifier spec', () {
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _shortWavePoses()),
            _demo(2, poses: _shortWavePoses(dx: 0.01)),
          ],
          requiredDemonstrations: 2,
        ),
      );

      expect(result.succeeded, isTrue, reason: result.failureReason);
      expect(result.spec, isNotNull);
      expect(
        result.spec!.activeFeatureIds.where(_isFaceOrHeadFeature),
        isEmpty,
      );
      expect(
        result.spec!.requiredFeatureIds.where(_isFaceOrHeadFeature),
        isEmpty,
      );
      expect(
        result.spec!.requiredFeatureIds.length,
        lessThanOrEqualTo(result.spec!.activeFeatureIds.length),
      );
      final bodyParts = result.selectedFeatureDiagnostics
          .map((diagnostic) => poseFeatureBodyPart(diagnostic.featureId))
          .toSet();
      expect(bodyParts, contains(anyOf('left wrist', 'right wrist')));
      expect(bodyParts, contains(anyOf('left elbow', 'right elbow')));
      expect(bodyParts, contains('shoulders'));
    });

    test('static examples report no meaningful movement', () {
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _staticPoses()),
            _demo(2, poses: _staticPoses()),
            _demo(3, poses: _staticPoses()),
          ],
        ),
      );

      expect(result.succeeded, isFalse);
      expect(result.failureReason, contains('static_capture'));
      expect(result.toDiagnosticsJson()['succeeded'], isFalse);
    });

    test('missing features and noisy inconsistent features are rejected', () {
      final missing = builder.build(
        _calibration(
          demos: [
            _demo(1),
            _demo(2),
            _demo(
              3,
              poses: _returnToStartPoses(missing: {'leftWrist', 'rightWrist'}),
            ),
          ],
        ),
      );

      expect(missing.succeeded, isTrue);
      expect(
        missing.spec!.activeFeatureIds,
        isNot(contains('landmark.leftWrist.y')),
      );

      final noisy = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _terminalPoses()),
            _demo(2, poses: _terminalPoses()),
            _demo(3, poses: _oppositeTerminalPoses()),
          ],
        ),
      );

      expect(noisy.succeeded, isFalse);
      expect(noisy.spec, isNull);
    });

    test('low shared feature coverage is rejected', () {
      final result = builder.build(
        _calibration(
          demos: [
            _demo(
              1,
              poses: _returnToStartPoses(
                missing: {
                  'leftWrist',
                  'rightWrist',
                  'leftElbow',
                  'rightElbow',
                  'leftKnee',
                  'rightKnee',
                },
              ),
            ),
            _demo(
              2,
              poses: _returnToStartPoses(
                missing: {
                  'leftWrist',
                  'rightWrist',
                  'leftElbow',
                  'rightElbow',
                  'leftAnkle',
                  'rightAnkle',
                },
              ),
            ),
            _demo(
              3,
              poses: _returnToStartPoses(
                missing: {
                  'leftShoulder',
                  'rightShoulder',
                  'leftHip',
                  'rightHip',
                },
              ),
            ),
          ],
        ),
      );

      expect(result.succeeded, isFalse);
    });
  });

  group('Thresholds, spec validation, and serialization', () {
    test(
      'thresholds stay in range and source demonstrations self-validate',
      () {
        final spec = builder.build(_calibration()).spec!;

        expect(spec.sequenceSimilarityThreshold, inInclusiveRange(0.50, 0.88));
        expect(
          spec.completionSimilarityThreshold,
          inInclusiveRange(0.72, 0.88),
        );
        expect(spec.resetSimilarityThreshold, inInclusiveRange(0.76, 0.92));
        expect(spec.minimumValidFeatureRatio, inInclusiveRange(0.35, 0.65));
        expect(spec.minimumVisibility, inInclusiveRange(0.30, 0.70));
        expect(
          spec.calibrationSummary.lowestPairwiseSimilarityScore,
          greaterThan(0.62),
        );
      },
    );

    test('valid spec round trips JSON and rejects malformed specs', () {
      final spec = builder.build(_calibration()).spec!;
      final encoded = jsonEncode(spec.toJson());
      final decoded = CustomPoseVerifierSpec.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(decoded.toDeterministicJson(), spec.toDeterministicJson());
      expect(
        () =>
            CustomPoseVerifierSpec.fromJson({...spec.toJson(), 'version': 99}),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseVerifierSpec.fromJson(
          {...spec.toJson()}..remove('movementName'),
        ),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseVerifierSpec.fromJson({
          ...spec.toJson(),
          'verifierType': 'preset_pose',
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseVerifierSpec.fromJson({
          ...spec.toJson(),
          'sequenceSimilarityThreshold': double.nan,
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseVerifierSpec.fromJson({
          ...spec.toJson(),
          'activeFeatureIds': ['landmark.leftWrist.y', 'landmark.leftWrist.y'],
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseVerifierSpec.fromJson({
          ...spec.toJson(),
          'activeFeatureIds': ['unknown.feature'],
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseVerifierSpec.fromJson({
          ...spec.toJson(),
          'canonicalSequence': [
            spec.canonicalSequence.last.toJson(),
            spec.canonicalSequence.first.toJson(),
          ],
          'expectedSequenceFrameCount': 2,
          'calibrationSummary': {
            ...spec.calibrationSummary.toJson(),
            'canonicalSequenceLength': 2,
          },
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => PoseTemplateFrame.fromJson({
          'position': 0.5,
          'features': {
            'landmark.leftWrist.y': {'value': double.infinity},
          },
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
    });
  });

  group('Stage 3 integration surface', () {
    testWidgets('summary builds and displays verifier summary', (tester) async {
      final result = builder.build(_calibration());

      expect(result.succeeded, isTrue);
      expect(result.spec, isNotNull);
      expect(result.spec!.verifierType, 'custom_pose_sequence');
      expect(result.spec!.measurementType, 'count');
    });
  });
}

CustomPoseCalibration _calibration({
  NormalizedPose? startPose,
  List<PoseDemonstration>? demos,
  CalibrationQuality? quality,
  int requiredDemonstrations = 3,
}) {
  final start =
      startPose ?? const PoseNormalizer().normalize(neutralStandingPose());
  final demonstrations = demos ?? [_demo(1), _demo(2), _demo(3)];
  final resolvedQuality =
      quality ??
      evaluateCalibrationQuality(
        startPose: start,
        startPoseStability: 1,
        demonstrations: demonstrations,
        requiredDemonstrations: requiredDemonstrations,
      );
  return CustomPoseCalibration(
    schemaVersion: poseCalibrationSchemaVersion,
    movementName: 'Overhead reach',
    startPose: start,
    demonstrations: demonstrations,
    quality: resolvedQuality,
    metadata: const CalibrationCaptureMetadata(
      capturedAtIso8601: '2026-01-01T00:00:00.000Z',
      cameraLensDirection: 'back',
      orientation: 'portraitUp',
      normalizerVersion: 'stage2-v1',
      deviceNote: 'test',
    ),
  );
}

PoseDemonstration _demo(
  int index, {
  List<NormalizedPose>? poses,
  double dx = 0,
}) {
  final sequence = poses ?? _returnToStartPoses(dx: dx);
  return PoseDemonstration(
    index: index,
    frames: _frames(sequence),
    durationMs: 1200,
    processedFrameCount: mathMax(8, sequence.length),
    validFrameCount: sequence.length,
    validFrameRatio: 1,
    averageVisibility: 1,
    accepted: true,
  );
}

List<PoseSequenceFrame> _frames(List<NormalizedPose> poses) {
  if (poses.isEmpty) return const [];
  return List.generate(poses.length, (index) {
    return PoseSequenceFrame(
      schemaVersion: normalizedPoseSchemaVersion,
      position: poses.length == 1 ? 0 : index / (poses.length - 1),
      elapsedMs: index * 120,
      pose: poses[index],
    );
  }, growable: false);
}

List<NormalizedPose> _returnToStartPoses({
  int leading = 2,
  int trailing = 2,
  double dx = 0,
  Set<String> missing = const {},
}) {
  const normalizer = PoseNormalizer();
  final neutral = normalizer.normalize(
    neutralStandingPose(dx: dx, missing: missing),
  );
  final overhead = normalizer.normalize(armsOverheadPose(dx: dx));
  return [
    for (var i = 0; i < leading; i++) neutral,
    overhead,
    overhead,
    neutral,
    for (var i = 0; i < trailing; i++) neutral,
  ];
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

List<NormalizedPose> _oppositeTerminalPoses() {
  const normalizer = PoseNormalizer();
  return [
    normalizer.normalize(neutralStandingPose()),
    normalizer.normalize(rightArmRaisedPose()),
    normalizer.normalize(rightArmRaisedPose()),
    normalizer.normalize(rightArmRaisedPose()),
  ];
}

List<NormalizedPose> _shortWavePoses({double dx = 0}) {
  const normalizer = PoseNormalizer();
  return [
    normalizer.normalize(neutralStandingPose(dx: dx)),
    normalizer.normalize(leftArmRaisedPose(dx: dx)),
    normalizer.normalize(leftArmRaisedPose(dx: dx)),
    normalizer.normalize(neutralStandingPose(dx: dx)),
  ];
}

List<NormalizedPose> _staticPoses() {
  final pose = const PoseNormalizer().normalize(neutralStandingPose());
  return [pose, pose, pose, pose, pose, pose];
}

int mathMax(int a, int b) => a > b ? a : b;

bool _isFaceOrHeadFeature(String featureId) {
  return poseFeatureBodyPart(featureId) == 'face/head';
}
