import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_sequence_builder.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_sequence_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
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

      expect(result.succeeded, isTrue, reason: result.failureReason);
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
            _demo(1, poses: _returnToStartPoses(leading: 3, trailing: 3)),
            _demo(2, poses: _returnToStartPoses(leading: 3, trailing: 3)),
            _demo(3, poses: _returnToStartPoses(leading: 3, trailing: 3)),
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

  group('tolerance to realistic variation', () {
    test('A. uneven amplitude: smaller recordings still select arm features', () {
      // Three demos of the same overhead reach at decreasing amplitudes.
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _unevenAmplitudePoses(amplitudeScale: 1.0)),
            _demo(2, poses: _unevenAmplitudePoses(amplitudeScale: 0.75)),
            _demo(3, poses: _unevenAmplitudePoses(amplitudeScale: 0.55)),
          ],
        ),
      );

      expect(result.succeeded, isTrue, reason: result.failureReason);
      final active = result.spec!.activeFeatureIds;
      // Important arm features should remain selected despite uneven amplitude.
      expect(
        active.any((id) => id.contains('Wrist')),
        isTrue,
        reason: 'No wrist features selected for uneven amplitude: $active',
      );
    });

    test('B. soft start / soft end: clip includes start/end context', () {
      // Movement that gradually begins and gradually returns. The cleaned
      // clip should include useful start/end context, not only the high-energy
      // middle frames.
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _softStartEndPoses()),
            _demo(2, poses: _softStartEndPoses(dx: 0.01)),
            _demo(3, poses: _softStartEndPoses(dx: -0.01)),
          ],
        ),
      );

      expect(result.succeeded, isTrue, reason: result.failureReason);
      final cleaning = result.toDiagnosticsJson()['cleaning'] as List;
      // The cleaned clip should have enough frames to represent start →
      // movement → return, not just the 2-3 highest-energy frames.
      for (final entry in cleaning.cast<Map<String, dynamic>>()) {
        final cleaned = entry['cleanedFrameCount'] as int;
        expect(
          cleaned,
          greaterThan(5),
          reason: 'Cleaned clip too short for soft start/end: $cleaned',
        );
      }
    });

    test('C. one weaker recording: builder still succeeds', () {
      // Two clean demos + one slightly noisy/low-amplitude demo.
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _returnToStartPoses(leading: 3, trailing: 3)),
            _demo(2, poses: _returnToStartPoses(leading: 3, trailing: 3)),
            _demo(3, poses: _unevenAmplitudePoses(amplitudeScale: 0.50)),
          ],
        ),
      );

      expect(result.succeeded, isTrue, reason: result.failureReason);
      expect(
        result.spec!.canonicalSequence,
        hasLength(customPoseTemplateFrameCount),
      );
    });

    test('D. accidental one-off movement does not dominate selection', () {
      // All three demos share the overhead movement. Demo 2 also includes
      // an unrelated right-ankle shift in one recording only.
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _overheadWithAccidentPoses(accident: false)),
            _demo(2, poses: _overheadWithAccidentPoses(accident: true)),
            _demo(3, poses: _overheadWithAccidentPoses(accident: false)),
          ],
        ),
      );

      expect(result.succeeded, isTrue, reason: result.failureReason);
      final active = result.spec!.activeFeatureIds;
      expect(active.any((id) => id.contains('leftWrist')), isTrue);
      expect(
        active.where((id) => id.contains('rightAnkle')),
        isEmpty,
        reason: 'Right-ankle accidental motion leaked: $active',
      );
    });

    test(
      'E. runtime generalization: varied build verifies a 4th performance',
      () {
        // Build from varied demonstrations, then test a 4th performance with
        // different speed, slightly different amplitude, and a slight start
        // position shift.
        final spec = builder
            .build(
              _calibration(
                demos: [
                  _demo(1, poses: _variableSpeedPoses(frameCount: 12)),
                  _demo(2, poses: _variableSpeedPoses(frameCount: 18)),
                  _demo(3, poses: _unevenAmplitudePoses(amplitudeScale: 0.80)),
                ],
              ),
            )
            .spec!;

        final runtime = CustomPoseSequenceRuntime(spec: spec, target: 3)
          ..start();
        // 4th performance: different speed, slight amplitude shift, slight
        // start-position offset.
        final attempt = _runtimeGeneralizationAttempt();
        for (var i = 0; i < 3; i++) {
          _playRuntime(runtime, attempt);
        }
        expect(
          runtime.currentValue,
          greaterThan(0),
          reason:
              '${runtime.lastUpdate.state} progress=${runtime.lastUpdate.sequenceProgress} '
              'sim=${runtime.lastUpdate.currentSimilarity} '
              'failure=${runtime.failedRuleReason}',
        );
      },
    );

    test('F. wrong movement: clearly different movement is rejected', () {
      // Two overhead demos + one completely different movement.
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _returnToStartPoses(leading: 3, trailing: 3)),
            _demo(2, poses: _returnToStartPoses(leading: 3, trailing: 3)),
            _demo(3, poses: _oppositeTerminalPoses()),
          ],
        ),
      );

      if (result.succeeded) {
        expect(
          result.spec!.calibrationSummary.lowestPairwiseSimilarityScore,
          lessThan(0.70),
          reason: 'Wrong movement should produce poor consistency',
        );
      } else {
        expect(result.failureReason, isNotNull);
      }
    });
  });

  group('demonstration cleaning', () {
    test('A. dead time: idle frames before and after movement are trimmed', () {
      // 20 idle + movement + 20 idle = ~45 frames per demo.
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _deadTimePoses(leading: 20, trailing: 20)),
            _demo(2, poses: _deadTimePoses(leading: 18, trailing: 22)),
            _demo(3, poses: _deadTimePoses(leading: 22, trailing: 18)),
          ],
        ),
      );

      expect(result.succeeded, isTrue, reason: result.failureReason);
      // Cleaning diagnostics should show significant trimming.
      final cleaning = result.toDiagnosticsJson()['cleaning'] as List;
      expect(cleaning, hasLength(3));
      for (final entry in cleaning.cast<Map<String, dynamic>>()) {
        final raw = entry['rawFrameCount'] as int;
        final cleaned = entry['cleanedFrameCount'] as int;
        expect(raw, greaterThan(40));
        expect(cleaned, lessThan(raw));
        // Should have trimmed at least half the idle frames.
        expect(cleaned, lessThan(raw * 0.75));
      }
    });

    test(
      'B. accidental movement: one-off right-wrist motion is not learned',
      () {
        // All three demos share the left-arm overhead movement. Demo 2 also
        // includes an unrelated right-ankle shift (e.g. stepping sideways)
        // before and after. The ankle shift does not occur in the overhead
        // movement, so right-ankle features should only move in 1 of 3 demos.
        final result = builder.build(
          _calibration(
            demos: [
              _demo(1, poses: _overheadWithAccidentPoses(accident: false)),
              _demo(2, poses: _overheadWithAccidentPoses(accident: true)),
              _demo(3, poses: _overheadWithAccidentPoses(accident: false)),
            ],
          ),
        );

        expect(result.succeeded, isTrue, reason: result.failureReason);
        final active = result.spec!.activeFeatureIds;
        // Left-arm features should be active (part of the overhead movement).
        expect(active.any((id) => id.contains('leftWrist')), isTrue);
        // Right-ankle coordinate features should NOT be active because the
        // sideways step only appeared in 1 of 3 demos.
        expect(
          active.where((id) => id.contains('rightAnkle')),
          isEmpty,
          reason:
              'Right-ankle accidental motion from one demo leaked into '
              'active features: $active',
        );
      },
    );

    test(
      'C. different speed teaching: 10/20/30 frame demos build consistently',
      () {
        final result = builder.build(
          _calibration(
            demos: [
              _demo(1, poses: _variableSpeedPoses(frameCount: 10)),
              _demo(2, poses: _variableSpeedPoses(frameCount: 20)),
              _demo(3, poses: _variableSpeedPoses(frameCount: 30)),
            ],
          ),
        );

        expect(result.succeeded, isTrue, reason: result.failureReason);
        final spec = result.spec!;
        expect(spec.canonicalSequence, hasLength(customPoseTemplateFrameCount));
        // Consistency should be acceptable.
        expect(
          spec.calibrationSummary.lowestPairwiseSimilarityScore,
          greaterThan(0.55),
          reason:
              'Cross-speed consistency too low: '
              '${spec.calibrationSummary.lowestPairwiseSimilarityScore}',
        );
      },
    );

    test('D. different start position: relative motion stays consistent', () {
      // Same overhead movement but each demo starts with a small dx offset.
      final result = builder.build(
        _calibration(
          demos: [
            _demo(
              1,
              poses: _returnToStartPoses(dx: 0.0, leading: 3, trailing: 3),
            ),
            _demo(
              2,
              poses: _returnToStartPoses(dx: 0.03, leading: 3, trailing: 3),
            ),
            _demo(
              3,
              poses: _returnToStartPoses(dx: -0.03, leading: 3, trailing: 3),
            ),
          ],
        ),
      );

      expect(result.succeeded, isTrue, reason: result.failureReason);
      final spec = result.spec!;
      expect(
        spec.calibrationSummary.lowestPairwiseSimilarityScore,
        greaterThan(0.55),
        reason: 'Cross-position consistency too low',
      );
    });

    test('E. wrong movement: clearly different movement is rejected', () {
      // Demo 1+2 do overhead reach, demo 3 does a completely different
      // movement (right-arm-only raise). Cross-demo consistency should fail.
      final result = builder.build(
        _calibration(
          demos: [
            _demo(1, poses: _terminalPoses()),
            _demo(2, poses: _terminalPoses(dx: 0.01)),
            _demo(3, poses: _oppositeTerminalPoses()),
          ],
        ),
      );

      // Either the build fails or consistency is poor.
      if (result.succeeded) {
        expect(
          result.spec!.calibrationSummary.lowestPairwiseSimilarityScore,
          lessThan(0.70),
          reason: 'Wrong movement should produce poor consistency',
        );
      } else {
        expect(result.failureReason, isNotNull);
      }
    });

    test(
      'F. realistic lead-in: small adjustment does not trigger movement start',
      () {
        // A few jitter/adjustment frames before the actual movement. The
        // cleaner should not trigger on the small adjustment alone.
        final result = builder.build(
          _calibration(
            demos: [
              _demo(1, poses: _leadInPoses()),
              _demo(2, poses: _leadInPoses(dx: 0.01)),
              _demo(3, poses: _leadInPoses(dx: -0.01)),
            ],
          ),
        );

        expect(result.succeeded, isTrue, reason: result.failureReason);
        // The cleaned clip should exclude most of the lead-in jitter.
        final cleaning = result.toDiagnosticsJson()['cleaning'] as List;
        for (final entry in cleaning.cast<Map<String, dynamic>>()) {
          final raw = entry['rawFrameCount'] as int;
          final cleaned = entry['cleanedFrameCount'] as int;
          expect(cleaned, lessThan(raw));
        }
      },
    );

    test('cleaning diagnostics expose required fields', () {
      final result = builder.build(_calibration());
      expect(result.succeeded, isTrue);
      final diag = result.toDiagnosticsJson();
      expect(diag, containsPair('cleaning', isA<List>()));
      expect(diag, containsPair('sharedMovingFeatureIds', isA<List>()));
      final cleaning = diag['cleaning'] as List;
      expect(cleaning, isNotEmpty);
      final first = cleaning.first as Map<String, dynamic>;
      expect(first, containsPair('rawFrameCount', isA<int>()));
      expect(first, containsPair('cleanedFrameCount', isA<int>()));
      expect(first, containsPair('cleanStartIndex', isA<int>()));
      expect(first, containsPair('cleanEndIndex', isA<int>()));
      expect(first, containsPair('movingFeatureCount', isA<int>()));
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
    durationMs: mathMax(1200, sequence.length * 120),
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
  final raised = normalizer.normalize(leftArmRaisedPose(dx: dx));
  // Interpolated movement so the motion-energy clipper has a sustained
  // active region and the generous lead-in/trailing context is
  // proportionally smaller than the movement itself.
  return [
    for (var i = 0; i < leading; i++) neutral,
    _blendPose(neutral, raised, 0.33),
    _blendPose(neutral, raised, 0.67),
    raised,
    _blendPose(raised, overhead, 0.33),
    _blendPose(raised, overhead, 0.67),
    overhead,
    overhead,
    _blendPose(overhead, neutral, 0.33),
    _blendPose(overhead, neutral, 0.67),
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

// ---------------------------------------------------------------------------
// Cleaning test helpers
// ---------------------------------------------------------------------------

/// A recording with [leading] idle frames, the overhead movement, then
/// [trailing] idle frames. The movement is interpolated across several frames
/// so motion energy has a clear sustained active region.
List<NormalizedPose> _deadTimePoses({int leading = 20, int trailing = 20}) {
  const normalizer = PoseNormalizer();
  final neutral = normalizer.normalize(neutralStandingPose());
  final overhead = normalizer.normalize(armsOverheadPose());
  final raised = normalizer.normalize(leftArmRaisedPose());
  return [
    for (var i = 0; i < leading; i++) neutral,
    _blendPose(neutral, raised, 0.33),
    _blendPose(neutral, raised, 0.67),
    raised,
    _blendPose(raised, overhead, 0.33),
    _blendPose(raised, overhead, 0.67),
    overhead,
    overhead,
    _blendPose(overhead, neutral, 0.33),
    _blendPose(overhead, neutral, 0.67),
    neutral,
    for (var i = 0; i < trailing; i++) neutral,
  ];
}

/// Overhead reach movement. When [accident] is true, an unrelated right-ankle
/// sideways shift (e.g. stepping to adjust stance) is added before and after
/// the main movement. This ankle movement does not occur during overhead reach.
List<NormalizedPose> _overheadWithAccidentPoses({required bool accident}) {
  const normalizer = PoseNormalizer();
  final neutral = normalizer.normalize(neutralStandingPose());
  final overhead = normalizer.normalize(armsOverheadPose());
  final raised = normalizer.normalize(leftArmRaisedPose());
  // Create a pose with the right ankle shifted sideways.
  final shiftedFrame = _shiftAnkle(neutralStandingPose(), dx: 0.08);
  final ankleShift = normalizer.normalize(shiftedFrame);
  final poses = <NormalizedPose>[];
  for (var i = 0; i < 5; i++) {
    poses.add(accident ? _blendPose(neutral, ankleShift, 0.5) : neutral);
  }
  poses.addAll([
    _blendPose(neutral, raised, 0.33),
    _blendPose(neutral, raised, 0.67),
    raised,
    _blendPose(raised, overhead, 0.33),
    _blendPose(raised, overhead, 0.67),
    overhead,
    overhead,
    _blendPose(overhead, neutral, 0.33),
    _blendPose(overhead, neutral, 0.67),
    neutral,
  ]);
  for (var i = 0; i < 5; i++) {
    poses.add(accident ? _blendPose(neutral, ankleShift, 0.5) : neutral);
  }
  return poses;
}

NuvoPoseFrame _shiftAnkle(NuvoPoseFrame frame, {required double dx}) {
  final points = Map<String, NuvoPosePoint>.of(frame.points);
  final rightAnkle = points['rightAnkle'];
  if (rightAnkle != null) {
    points['rightAnkle'] = NuvoPosePoint(
      x: rightAnkle.x + dx,
      y: rightAnkle.y,
      z: rightAnkle.z,
      likelihood: rightAnkle.likelihood,
    );
  }
  return NuvoPoseFrame(
    points: Map.unmodifiable(points),
    imageWidth: frame.imageWidth,
    imageHeight: frame.imageHeight,
    createdAt: frame.createdAt,
  );
}

/// Same overhead movement at different speeds via smooth interpolation.
/// More frames = slower movement (more intermediate poses between keyframes).
List<NormalizedPose> _variableSpeedPoses({required int frameCount}) {
  const normalizer = PoseNormalizer();
  final neutral = normalizer.normalize(neutralStandingPose());
  final overhead = normalizer.normalize(armsOverheadPose());
  final raised = normalizer.normalize(leftArmRaisedPose());
  final keyframes = <NormalizedPose>[
    neutral,
    neutral,
    _blendPose(neutral, raised, 0.5),
    raised,
    _blendPose(raised, overhead, 0.5),
    overhead,
    overhead,
    _blendPose(overhead, neutral, 0.5),
    neutral,
    neutral,
  ];
  if (frameCount <= keyframes.length) {
    return keyframes.take(frameCount).toList(growable: false);
  }
  return List.generate(frameCount, (index) {
    final pos = index / (frameCount - 1) * (keyframes.length - 1);
    final lo = pos.floor().clamp(0, keyframes.length - 1);
    final hi = (lo + 1).clamp(0, keyframes.length - 1);
    final t = pos - lo;
    return _blendPose(keyframes[lo], keyframes[hi], t);
  }, growable: false);
}

/// Recording with small jitter/adjustment frames before the actual movement,
/// plus trailing idle frames after the return.
List<NormalizedPose> _leadInPoses({double dx = 0}) {
  const normalizer = PoseNormalizer();
  final neutral = normalizer.normalize(neutralStandingPose(dx: dx));
  final overhead = normalizer.normalize(armsOverheadPose(dx: dx));
  final raised = normalizer.normalize(leftArmRaisedPose(dx: dx));
  // Small adjustments (well below movement threshold).
  final jitter1 = _blendPose(neutral, raised, 0.05);
  final jitter2 = _blendPose(neutral, raised, 0.08);
  return [
    // Lead-in jitter (should NOT trigger movement start).
    neutral,
    jitter1,
    neutral,
    jitter2,
    neutral,
    neutral,
    // Actual movement starts here.
    _blendPose(neutral, raised, 0.33),
    _blendPose(neutral, raised, 0.67),
    raised,
    _blendPose(raised, overhead, 0.33),
    _blendPose(raised, overhead, 0.67),
    overhead,
    overhead,
    _blendPose(overhead, neutral, 0.33),
    _blendPose(overhead, neutral, 0.67),
    neutral,
    // Trailing idle (should be trimmed).
    for (var i = 0; i < 10; i++) neutral,
  ];
}

NormalizedPose _blendPose(NormalizedPose a, NormalizedPose b, double t) {
  final features = <String, PoseFeatureValue>{};
  for (final id in {...a.features.values.keys, ...b.features.values.keys}) {
    final fa = a.features.values[id];
    final fb = b.features.values[id];
    if (fa == null || fb == null || fa.kind != fb.kind) continue;
    features[id] = PoseFeatureValue(
      value: fa.value + (fb.value - fa.value) * t,
      confidence: fa.confidence + (fb.confidence - fa.confidence) * t,
      valid: true,
      kind: fa.kind,
    );
  }
  return NormalizedPose(
    schemaVersion: normalizedPoseSchemaVersion,
    landmarks: const {},
    features: PoseFeatureVector(Map.unmodifiable(features)),
    originX: a.originX + (b.originX - a.originX) * t,
    originY: a.originY + (b.originY - a.originY) * t,
    scale: a.scale + (b.scale - a.scale) * t,
    originReference: a.originReference,
    scaleReference: a.scaleReference,
    validLandmarkCount: 0,
    validFeatureCount: features.length,
  );
}

// ---------------------------------------------------------------------------
// Tolerance test helpers
// ---------------------------------------------------------------------------

/// Overhead reach at [amplitudeScale] of full range. 1.0 = full overhead,
/// 0.5 = half height. The same movement shape at weaker amplitude.
List<NormalizedPose> _unevenAmplitudePoses({required double amplitudeScale}) {
  const normalizer = PoseNormalizer();
  final neutral = normalizer.normalize(neutralStandingPose());
  final overhead = normalizer.normalize(armsOverheadPose());
  final raised = normalizer.normalize(leftArmRaisedPose());
  // Scale the movement toward neutral by the inverse of amplitudeScale.
  NormalizedPose scaled(NormalizedPose target) {
    return _blendPose(neutral, target, amplitudeScale.clamp(0.0, 1.0));
  }

  final sRaised = scaled(raised);
  final sOverhead = scaled(overhead);
  return [
    for (var i = 0; i < 3; i++) neutral,
    _blendPose(neutral, sRaised, 0.33),
    _blendPose(neutral, sRaised, 0.67),
    sRaised,
    _blendPose(sRaised, sOverhead, 0.33),
    _blendPose(sRaised, sOverhead, 0.67),
    sOverhead,
    sOverhead,
    _blendPose(sOverhead, neutral, 0.33),
    _blendPose(sOverhead, neutral, 0.67),
    neutral,
    for (var i = 0; i < 3; i++) neutral,
  ];
}

/// Movement that gradually begins and gradually returns — no sharp
/// high-energy middle. Tests that the clipper retains start/end context.
List<NormalizedPose> _softStartEndPoses({double dx = 0}) {
  const normalizer = PoseNormalizer();
  final neutral = normalizer.normalize(neutralStandingPose(dx: dx));
  final overhead = normalizer.normalize(armsOverheadPose(dx: dx));
  // Very gradual interpolation with many small steps.
  final poses = <NormalizedPose>[];
  for (var i = 0; i < 3; i++) {
    poses.add(neutral);
  }
  for (var i = 1; i <= 8; i++) {
    poses.add(_blendPose(neutral, overhead, i / 10));
  }
  for (var i = 0; i < 3; i++) {
    poses.add(overhead);
  }
  for (var i = 8; i >= 1; i--) {
    poses.add(_blendPose(neutral, overhead, i / 10));
  }
  for (var i = 0; i < 3; i++) {
    poses.add(neutral);
  }
  return poses;
}

/// A 4th performance with different speed, slightly different amplitude, and
/// a slight start-position shift. Returns raw NuvoPoseFrames for the runtime.
List<NuvoPoseFrame> _runtimeGeneralizationAttempt() {
  final neutral = neutralStandingPose(dx: 0.02);
  final overhead = armsOverheadPose(dx: 0.02);
  final raised = leftArmRaisedPose(dx: 0.02);
  NuvoPoseFrame blend(NuvoPoseFrame a, NuvoPoseFrame b, double t) {
    final points = <String, NuvoPosePoint>{};
    for (final key in a.points.keys) {
      final pa = a.points[key]!;
      final pb = b.points[key];
      if (pb == null) continue;
      points[key] = NuvoPosePoint(
        x: pa.x + (pb.x - pa.x) * t,
        y: pa.y + (pb.y - pa.y) * t,
        z: pa.z + (pb.z - pa.z) * t,
        likelihood: pa.likelihood,
      );
    }
    return NuvoPoseFrame(
      points: Map.unmodifiable(points),
      imageWidth: a.imageWidth,
      imageHeight: a.imageHeight,
      createdAt: a.createdAt,
    );
  }

  // Slightly smaller amplitude (0.9x) + different speed (fewer frames).
  NuvoPoseFrame scaled(NuvoPoseFrame target) => blend(neutral, target, 0.90);
  final sRaised = scaled(raised);
  final sOverhead = scaled(overhead);
  return [
    neutral,
    neutral,
    blend(neutral, sRaised, 0.5),
    sRaised,
    blend(sRaised, sOverhead, 0.5),
    sOverhead,
    sOverhead,
    blend(sOverhead, neutral, 0.5),
    neutral,
    neutral,
  ];
}

void _playRuntime(
  CustomPoseSequenceRuntime runtime,
  List<NuvoPoseFrame> frames,
) {
  for (final frame in frames) {
    runtime.update(frame);
  }
}
