import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/normalized_pose.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_sequence_frame.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_similarity.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'fixtures/pose_fixtures.dart';

void main() {
  const normalizer = PoseNormalizer();
  const similarity = PoseSimilarity();

  group('pose normalization', () {
    test('is stable across translation', () {
      final base = normalizer.normalize(neutralStandingPose());
      final translated = normalizer.normalize(
        neutralStandingPose(dx: 0.12, dy: -0.08),
      );

      expect(base.originReference, 'hip_midpoint');
      expect(base.scaleReference, 'shoulder_width');
      _expectLandmarkClose(base, translated, 'leftWrist');
      _expectLandmarkClose(base, translated, 'rightAnkle');
      expect(
        similarity.compare(base, translated).similarity,
        greaterThan(0.99),
      );
    });

    test('is stable across scale changes', () {
      final base = normalizer.normalize(neutralStandingPose());
      final scaled = normalizer.normalize(neutralStandingPose(scale: 0.68));

      _expectLandmarkClose(base, scaled, 'leftElbow');
      _expectLandmarkClose(base, scaled, 'rightKnee');
      expect(similarity.compare(base, scaled).similarity, greaterThan(0.99));
    });

    test('scores noisy versions higher than different poses', () {
      final base = normalizer.normalize(neutralStandingPose());
      final noisy = normalizer.normalize(
        neutralStandingPose(dx: 0.01, dy: -0.01, scale: 1.03),
      );
      final overhead = normalizer.normalize(armsOverheadPose());

      final sameScore = similarity.compare(base, noisy);
      final differentScore = similarity.compare(base, overhead);

      expect(sameScore.isValid, isTrue);
      expect(differentScore.isValid, isTrue);
      expect(sameScore.similarity, greaterThan(0.95));
      expect(differentScore.similarity, lessThan(sameScore.similarity - 0.15));
    });

    test('keeps left and right arm actions distinguishable', () {
      final left = normalizer.normalize(leftArmRaisedPose());
      final right = normalizer.normalize(rightArmRaisedPose());
      final leftAgain = normalizer.normalize(leftArmRaisedPose(dx: 0.02));

      final sameSide = similarity.compare(left, leftAgain);
      final oppositeSide = similarity.compare(left, right);

      expect(sameSide.similarity, greaterThan(0.98));
      expect(oppositeSide.similarity, lessThan(sameSide.similarity - 0.20));
    });

    test('missing landmarks do not become valid zero features', () {
      final full = normalizer.normalize(neutralStandingPose());
      final missing = normalizer.normalize(
        neutralStandingPose(
          missing: {'leftWrist', 'rightWrist', 'leftElbow', 'rightElbow'},
        ),
      );
      final result = const PoseSimilarity(
        minValidFeatureRatio: 0.90,
      ).compare(full, missing);

      expect(missing.landmarks.containsKey('leftWrist'), isFalse);
      expect(
        missing.features.values.containsKey('landmark.leftWrist.x'),
        isFalse,
      );
      expect(missing.validFeatureCount, lessThan(full.validFeatureCount));
      expect(result.isValid, isFalse);
      expect(result.invalidReason, 'insufficient_valid_features');
      expect(result.validFeatureRatio, lessThan(0.90));
    });

    test('low-confidence landmarks are excluded consistently', () {
      final lowConfidence = normalizer.normalize(
        neutralStandingPose(
          likelihoods: {'leftWrist': 0.10, 'rightWrist': 0.10},
        ),
      );

      expect(lowConfidence.landmarks.containsKey('leftWrist'), isFalse);
      expect(lowConfidence.landmarks.containsKey('rightWrist'), isFalse);
      expect(
        lowConfidence.features.values.keys.any((key) => key.contains('Wrist')),
        isFalse,
      );
    });

    test('uses documented scale fallbacks where possible', () {
      final noShoulders = normalizer.normalize(
        neutralStandingPose(missing: {'leftShoulder', 'rightShoulder'}),
      );
      final noHips = normalizer.normalize(
        neutralStandingPose(missing: {'leftHip', 'rightHip'}),
      );

      expect(noShoulders.isValid, isTrue);
      expect(noShoulders.originReference, 'hip_midpoint');
      expect(noShoulders.scaleReference, 'hip_width');
      expect(noHips.isValid, isTrue);
      expect(noHips.originReference, 'shoulder_midpoint');
      expect(noHips.scaleReference, 'shoulder_width');
    });

    test('degenerate scale inputs fail clearly without non-finite values', () {
      final pose = normalizer.normalize(
        NuvoPoseFrame(
          points: {
            'leftShoulder': const NuvoPosePoint(
              x: 0.5,
              y: 0.5,
              z: 0,
              likelihood: 0.95,
            ),
            'rightShoulder': const NuvoPosePoint(
              x: 0.5,
              y: 0.5,
              z: 0,
              likelihood: 0.95,
            ),
            'leftHip': const NuvoPosePoint(
              x: 0.5,
              y: 0.5,
              z: 0,
              likelihood: 0.95,
            ),
            'rightHip': const NuvoPosePoint(
              x: 0.5,
              y: 0.5,
              z: 0,
              likelihood: 0.95,
            ),
          },
          imageWidth: 1000,
          imageHeight: 1000,
          createdAt: DateTime.utc(2026),
        ),
      );

      expect(pose.isValid, isFalse);
      expect(pose.invalidReason, 'missing_scale_landmarks');
      expect(pose.originX.isFinite, isTrue);
      expect(pose.originY.isFinite, isTrue);
      expect(pose.scale.isFinite, isTrue);
    });
  });

  group('pose serialization', () {
    test('normalized pose, feature vector, and sequence frame round trip', () {
      final pose = normalizer.normalize(handsNearKneesPose());
      final decodedPose = NormalizedPose.fromJson(
        jsonDecode(jsonEncode(pose.toJson())) as Map<String, dynamic>,
      );
      final decodedFeatures = PoseFeatureVector.fromJson(
        jsonDecode(jsonEncode(pose.features.toJson())) as Map<String, dynamic>,
      );
      final frame = PoseSequenceFrame(
        schemaVersion: normalizedPoseSchemaVersion,
        position: 0.4,
        elapsedMs: 240,
        pose: pose,
      );
      final decodedFrame = PoseSequenceFrame.fromJson(
        jsonDecode(jsonEncode(frame.toJson())) as Map<String, dynamic>,
      );

      expect(decodedPose.schemaVersion, normalizedPoseSchemaVersion);
      expect(decodedPose.landmarks.length, pose.landmarks.length);
      expect(decodedPose.features.values.length, pose.features.values.length);
      expect(decodedFeatures.values.length, pose.features.values.length);
      expect(decodedFrame.schemaVersion, normalizedPoseSchemaVersion);
      expect(decodedFrame.position, 0.4);
      expect(decodedFrame.elapsedMs, 240);
      expect(decodedFrame.pose.validFeatureCount, pose.validFeatureCount);
    });

    test('rejects malformed normalized pose JSON', () {
      final json = normalizer.normalize(neutralStandingPose()).toJson();

      expect(
        () => NormalizedPose.fromJson({...json, 'version': 99}),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => NormalizedPose.fromJson({...json}..remove('landmarks')),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => NormalizedPose.fromJson({
          ...json,
          'landmarks': {
            ...json['landmarks'] as Map<String, dynamic>,
            'mysteryJoint': {
              'x': 0,
              'y': 0,
              'z': 0,
              'confidence': 1,
              'valid': true,
            },
          },
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => NormalizedPose.fromJson({...json, 'originX': '0.5'}),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => NormalizedPose.fromJson({...json, 'originX': double.nan}),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => NormalizedPose.fromJson({
          ...json,
          'features': {'bad': []},
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
    });

    test('rejects malformed feature vector and sequence frame JSON', () {
      final pose = normalizer.normalize(neutralStandingPose());
      expect(
        () => PoseFeatureVector.fromJson({
          'version': normalizedPoseSchemaVersion,
          'values': {
            'bad': {
              'value': 0,
              'confidence': 1,
              'valid': true,
              'kind': 'unknown',
            },
          },
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => PoseSequenceFrame.fromJson({
          'version': 99,
          'position': 0,
          'elapsedMs': 0,
          'pose': pose.toJson(),
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => PoseSequenceFrame.fromJson({
          'version': normalizedPoseSchemaVersion,
          'position': double.infinity,
          'elapsedMs': 0,
          'pose': pose.toJson(),
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
    });

    test('normalization and encoding are deterministic', () {
      final first = normalizer.normalize(neutralStandingPose()).toJson();
      final second = normalizer.normalize(neutralStandingPose()).toJson();

      expect(jsonEncode(first), jsonEncode(second));
    });
  });
}

void _expectLandmarkClose(NormalizedPose a, NormalizedPose b, String id) {
  final left = a.landmarks[id]!;
  final right = b.landmarks[id]!;
  expect(left.x, closeTo(right.x, 0.000001), reason: '$id.x');
  expect(left.y, closeTo(right.y, 0.000001), reason: '$id.y');
}
