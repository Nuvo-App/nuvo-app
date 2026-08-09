import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/features/races/ai/custom_pose/normalized_pose.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_models.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/presentation/custom_pose/learned_movement_preview.dart';

import 'fixtures/pose_fixtures.dart';

CustomPoseVerifierSpec _spec({
  required NormalizedPose startPose,
  required List<PoseTemplateFrame> canonicalSequence,
}) {
  return CustomPoseVerifierSpec(
    schemaVersion: customPoseVerifierSpecSchemaVersion,
    verifierType: customPoseVerifierType,
    movementName: 'Test',
    measurementType: customPoseMeasurementType,
    startPose: startPose,
    completionPose: startPose,
    completionStrategy: CustomPoseCompletionStrategy.completionAtTerminalPose,
    canonicalSequence: canonicalSequence,
    requiredFeatureIds: const [],
    activeFeatureIds: const [],
    sequenceSimilarityThreshold: 0.7,
    completionSimilarityThreshold: 0.8,
    resetSimilarityThreshold: 0.9,
    minimumValidFeatureRatio: 0.3,
    minimumVisibility: 0.5,
    cooldownMs: 500,
    expectedSequenceFrameCount: canonicalSequence.length,
    calibrationSummary: CustomPoseCalibrationSummary(
      sourceCalibrationSchemaVersion: poseCalibrationSchemaVersion,
      demonstrationCount: 3,
      selectedActiveFeatureCount: 0,
      requiredFeatureCount: 0,
      canonicalSequenceLength: canonicalSequence.length,
      pairwiseSimilarityScores: const {},
      overallConsistencyScore: 1.0,
      lowestPairwiseSimilarityScore: 1.0,
      sequenceSimilarityThreshold: 0.7,
      completionSimilarityThreshold: 0.8,
      resetSimilarityThreshold: 0.9,
      minimumValidFeatureRatio: 0.3,
      minimumVisibility: 0.5,
      cooldownMs: 500,
      completionStrategy: CustomPoseCompletionStrategy.completionAtTerminalPose,
      builderVersion: 'test',
    ),
  );
}

PoseTemplateFrame _frame(
  double position,
  Map<String, PoseTemplateFeature> features,
) {
  return PoseTemplateFrame(position: position, features: features);
}

PoseTemplateFeature _feature(double value) {
  return PoseTemplateFeature(
    value: value,
    confidence: 0.9,
    reliability: 0.9,
    allowedVariation: 0.1,
    contributingDemonstrationCount: 3,
    kind: 'coord',
  );
}

void main() {
  const normalizer = PoseNormalizer();
  final startPose = normalizer.normalize(neutralStandingPose());
  final leftWristStart = startPose.landmarks['leftWrist']!;

  group('buildLearnedMovementFrames', () {
    test(
      'startPose remains the base for landmarks not in canonical features',
      () {
        final frames = buildLearnedMovementFrames(
          _spec(
            startPose: startPose,
            canonicalSequence: [
              _frame(0.0, {
                'landmark.leftWrist.x': _feature(0.5),
                'landmark.leftWrist.y': _feature(0.4),
              }),
              _frame(1.0, {
                'landmark.leftWrist.x': _feature(0.6),
                'landmark.leftWrist.y': _feature(0.3),
              }),
            ],
          ),
        );

        expect(frames.length, 2);
        // rightWrist is not in canonical features -> stays at startPose
        final rightWrist0 = frames[0].landmarks['rightWrist']!;
        final rightWristStart = startPose.landmarks['rightWrist']!;
        expect(rightWrist0.x, rightWristStart.x);
        expect(rightWrist0.y, rightWristStart.y);
        // same in frame 2
        final rightWrist1 = frames[1].landmarks['rightWrist']!;
        expect(rightWrist1.x, rightWristStart.x);
        expect(rightWrist1.y, rightWristStart.y);
      },
    );

    test('landmark.leftWrist.x/y canonical features move the left wrist', () {
      final frames = buildLearnedMovementFrames(
        _spec(
          startPose: startPose,
          canonicalSequence: [
            _frame(0.0, {
              'landmark.leftWrist.x': _feature(0.5),
              'landmark.leftWrist.y': _feature(0.4),
            }),
            _frame(1.0, {
              'landmark.leftWrist.x': _feature(0.9),
              'landmark.leftWrist.y': _feature(0.1),
            }),
          ],
        ),
      );

      final f0 = frames[0].landmarks['leftWrist']!;
      expect(f0.x, 0.5);
      expect(f0.y, 0.4);
      final f1 = frames[1].landmarks['leftWrist']!;
      expect(f1.x, 0.9);
      expect(f1.y, 0.1);
      // ensure it actually moved from start
      expect(f1.x, isNot(leftWristStart.x));
      expect(f1.y, isNot(leftWristStart.y));
    });

    test(
      'angle.* and distance.* features do not alter skeleton coordinates',
      () {
        final frames = buildLearnedMovementFrames(
          _spec(
            startPose: startPose,
            canonicalSequence: [
              _frame(0.0, {
                'angle.leftElbow': const PoseTemplateFeature(
                  value: 0.5,
                  confidence: 0.9,
                  reliability: 0.9,
                  allowedVariation: 0.1,
                  contributingDemonstrationCount: 3,
                  kind: 'angle',
                ),
                'distance.leftWrist-rightWrist': const PoseTemplateFeature(
                  value: 0.3,
                  confidence: 0.9,
                  reliability: 0.9,
                  allowedVariation: 0.1,
                  contributingDemonstrationCount: 3,
                  kind: 'distance',
                ),
              }),
            ],
          ),
        );

        // All landmarks should remain at startPose values
        for (final entry in startPose.landmarks.entries) {
          if (!entry.value.valid) continue;
          final previewPoint = frames[0].landmarks[entry.key];
          expect(previewPoint, isNotNull);
          expect(previewPoint!.x, entry.value.x);
          expect(previewPoint.y, entry.value.y);
        }
      },
    );

    test('unknown feature ids do not crash', () {
      expect(
        () => buildLearnedMovementFrames(
          _spec(
            startPose: startPose,
            canonicalSequence: [
              _frame(0.0, {
                'unknown.feature': _feature(0.5),
                'landmark.nonExistentLandmark.x': _feature(0.5),
                'landmark.leftWrist.z': _feature(0.5),
                'notalandmark': _feature(0.5),
              }),
            ],
          ),
        ),
        returnsNormally,
      );
    });

    test(
      'preview renders with an empty canonical sequence without crashing',
      () {
        final frames = buildLearnedMovementFrames(
          _spec(startPose: startPose, canonicalSequence: const []),
        );
        expect(frames, isEmpty);

        // bounds should still compute from startPose
        final bounds = computeLearnedMovementBounds(startPose, frames);
        expect(bounds.minX, isNot(double.infinity));
        expect(bounds.maxX, isNot(double.negativeInfinity));
      },
    );
  });

  group('LearnedMovementPreview widget', () {
    testWidgets('timer is cancelled on dispose without test errors', (
      WidgetTester tester,
    ) async {
      final spec = _spec(
        startPose: startPose,
        canonicalSequence: [
          _frame(0.0, {
            'landmark.leftWrist.x': _feature(0.5),
            'landmark.leftWrist.y': _feature(0.4),
          }),
          _frame(0.5, {
            'landmark.leftWrist.x': _feature(0.7),
            'landmark.leftWrist.y': _feature(0.3),
          }),
          _frame(1.0, {
            'landmark.leftWrist.x': _feature(0.9),
            'landmark.leftWrist.y': _feature(0.1),
          }),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LearnedMovementPreview(spec: spec)),
        ),
      );
      await tester.pump();
      // Let a few frames tick
      await tester.pump(const Duration(milliseconds: 250));
      // Dispose
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      // No pending timer exceptions thrown
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with empty canonical sequence without crashing', (
      WidgetTester tester,
    ) async {
      final spec = _spec(startPose: startPose, canonicalSequence: const []);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LearnedMovementPreview(spec: spec)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(LearnedMovementPreview), findsOneWidget);
    });
  });
}
