import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/normalized_pose.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_flow.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_models.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_quality.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_demonstration_capture.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_sequence_frame.dart';
import 'package:nuvo/features/races/ai/custom_pose/stable_pose_capture.dart';

import 'fixtures/pose_fixtures.dart';

void main() {
  const normalizer = PoseNormalizer();

  group('PoseAverager', () {
    test('equivalent poses average correctly and remain finite', () {
      final poses = [
        normalizer.normalize(neutralStandingPose()),
        normalizer.normalize(neutralStandingPose(dx: 0.02)),
        normalizer.normalize(neutralStandingPose(dx: -0.02)),
      ];

      final average = const PoseAverager(minPoseCount: 2).average(poses);

      expect(average.isValid, isTrue);
      expect(average.landmarks['leftWrist']!.x.isFinite, isTrue);
      expect(average.features.values, contains('landmark.leftWrist.x'));
    });

    test('missing features are excluded when shared coverage is too low', () {
      final poses = [
        normalizer.normalize(neutralStandingPose()),
        normalizer.normalize(neutralStandingPose(missing: {'leftWrist'})),
        normalizer.normalize(neutralStandingPose(missing: {'leftWrist'})),
      ];

      final average = const PoseAverager(
        minPoseCount: 2,
        minSharedRatio: 0.70,
      ).average(poses);

      expect(average.landmarks.containsKey('leftWrist'), isFalse);
      expect(
        average.features.values.containsKey('landmark.leftWrist.x'),
        isFalse,
      );
    });

    test('left and right identifiers remain distinct', () {
      final average = const PoseAverager(minPoseCount: 2).average([
        normalizer.normalize(leftArmRaisedPose()),
        normalizer.normalize(leftArmRaisedPose(dx: 0.01)),
      ]);

      expect(
        average.landmarks['leftWrist']!.y,
        lessThan(average.landmarks['rightWrist']!.y),
      );
    });

    test('invalid inputs fail clearly', () {
      expect(
        () => const PoseAverager(
          minPoseCount: 2,
        ).average([normalizer.normalize(neutralStandingPose())]),
        throwsA(isA<PoseDataFormatException>()),
      );
    });
  });

  group('StablePoseCapture', () {
    test('stable frames accumulate and capture averaged pose', () {
      final capture = StablePoseCapture(requiredStableFrames: 4);
      final start = DateTime.utc(2026);
      StablePoseCaptureUpdate? update;
      for (var i = 0; i < 4; i++) {
        update = capture.addFrame(
          normalizer.normalize(neutralStandingPose(dx: i * 0.001)),
          start.add(Duration(milliseconds: i * 120)),
        );
      }

      expect(update!.captured, isTrue);
      expect(update.pose, isNotNull);
      expect(update.pose!.landmarks['leftWrist']!.x.isFinite, isTrue);
    });

    test('movement resets stability collection', () {
      final capture = StablePoseCapture(requiredStableFrames: 4);
      final start = DateTime.utc(2026);
      capture.addFrame(normalizer.normalize(neutralStandingPose()), start);
      capture.addFrame(
        normalizer.normalize(neutralStandingPose(dx: 0.001)),
        start.add(const Duration(milliseconds: 100)),
      );
      final update = capture.addFrame(
        normalizer.normalize(armsOverheadPose()),
        start.add(const Duration(milliseconds: 200)),
      );

      expect(update.captured, isFalse);
      expect(update.stableFrameCount, 1);
    });

    test('low-validity frame resets collection', () {
      final capture = StablePoseCapture(requiredStableFrames: 4);
      final start = DateTime.utc(2026);
      capture.addFrame(normalizer.normalize(neutralStandingPose()), start);
      final update = capture.addFrame(
        normalizer.normalize(
          neutralStandingPose(
            missing: {'leftHip', 'rightHip', 'leftShoulder', 'rightShoulder'},
          ),
        ),
        start.add(const Duration(milliseconds: 100)),
      );

      expect(update.captured, isFalse);
      expect(update.stableFrameCount, 0);
    });

    test('timeout returns clear failure', () {
      final capture = StablePoseCapture(
        requiredStableFrames: 10,
        timeout: const Duration(milliseconds: 300),
      );
      final start = DateTime.utc(2026);
      capture.addFrame(normalizer.normalize(neutralStandingPose()), start);
      final update = capture.addFrame(
        normalizer.normalize(neutralStandingPose(dx: 0.3)),
        start.add(const Duration(milliseconds: 400)),
      );

      expect(update.status, StablePoseCaptureStatus.failed);
      expect(update.message, isNotEmpty);
    });
  });

  group('PoseDemonstrationCapture', () {
    test('valid demonstration is accepted and bounded', () {
      final capture = PoseDemonstrationCapture(index: 1, maxFrameCount: 5);
      final start = DateTime.utc(2026);
      capture.start(start);
      for (var i = 0; i < 12; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose(dx: i * 0.001)),
          start.add(Duration(milliseconds: i * 120)),
        );
      }
      final demo = capture.finish(
        start.add(const Duration(milliseconds: 1400)),
      );

      expect(demo.accepted, isTrue);
      expect(demo.frames.length, 5);
      expect(demo.validFrameRatio, greaterThan(0.6));
    });

    test(
      'rejects too few frames, low valid ratio, too short, and interruption',
      () {
        final start = DateTime.utc(2026);
        final few = PoseDemonstrationCapture(index: 1)..start(start);
        few.addFrame(normalizer.normalize(neutralStandingPose()), start);
        expect(
          few
              .finish(start.add(const Duration(milliseconds: 900)))
              .rejectionReason,
          'too_few_processed_frames',
        );

        final low = PoseDemonstrationCapture(index: 2)..start(start);
        for (var i = 0; i < 8; i++) {
          low.addFrame(
            i == 0
                ? normalizer.normalize(neutralStandingPose())
                : normalizer.normalize(
                    neutralStandingPose(
                      missing: {
                        'leftHip',
                        'rightHip',
                        'leftShoulder',
                        'rightShoulder',
                      },
                    ),
                  ),
            start.add(Duration(milliseconds: i * 120)),
          );
        }
        expect(
          low
              .finish(start.add(const Duration(milliseconds: 1000)))
              .rejectionReason,
          'low_valid_frame_ratio',
        );

        final short = PoseDemonstrationCapture(index: 3)..start(start);
        for (var i = 0; i < 8; i++) {
          short.addFrame(normalizer.normalize(neutralStandingPose()), start);
        }
        expect(
          short
              .finish(start.add(const Duration(milliseconds: 300)))
              .rejectionReason,
          'too_short',
        );

        final interrupted = PoseDemonstrationCapture(index: 1)..start(start);
        interrupted.interrupt();
        expect(
          interrupted
              .finish(start.add(const Duration(milliseconds: 900)))
              .rejectionReason,
          'capture_interrupted',
        );
      },
    );
  });

  group('Calibration readiness and serialization', () {
    test('complete calibration becomes ready and round trips JSON', () {
      final start = normalizer.normalize(neutralStandingPose());
      final demos = [_demo(1), _demo(2), _demo(3)];
      final quality = evaluateCalibrationQuality(
        startPose: start,
        startPoseStability: 1,
        demonstrations: demos,
      );
      final calibration = CustomPoseCalibration(
        schemaVersion: poseCalibrationSchemaVersion,
        movementName: 'Side reach',
        startPose: start,
        demonstrations: demos,
        quality: quality,
        metadata: const CalibrationCaptureMetadata(
          capturedAtIso8601: '2026-01-01T00:00:00.000Z',
          cameraLensDirection: 'back',
          orientation: 'portraitUp',
          normalizerVersion: 'stage2-v1',
          deviceNote: 'test',
        ),
      );
      final decoded = CustomPoseCalibration.fromJson(
        jsonDecode(jsonEncode(calibration.toJson())) as Map<String, dynamic>,
      );

      expect(quality.readyForBuilder, isTrue);
      expect(decoded.movementName, 'Side reach');
      expect(decoded.demonstrations.length, 3);
      expect(decoded.quality.readyForBuilder, isTrue);
    });

    test(
      'invalid start pose or one failed demonstration prevents readiness',
      () {
        final quality = evaluateCalibrationQuality(
          startPose: null,
          startPoseStability: 0,
          demonstrations: [_demo(1), _demo(2), _demo(3, accepted: false)],
        );

        expect(quality.readyForBuilder, isFalse);
        expect(quality.reasons, contains('start_pose_invalid'));
        expect(quality.reasons, contains('requires_three_demonstrations'));
        expect(
          quality.reasons.any((reason) => reason.startsWith('demo_3')),
          isTrue,
        );
      },
    );

    test('calibration JSON rejects malformed data', () {
      final start = normalizer.normalize(neutralStandingPose());
      final calibration = CustomPoseCalibration(
        schemaVersion: poseCalibrationSchemaVersion,
        movementName: 'Tap',
        startPose: start,
        demonstrations: [_demo(1), _demo(2), _demo(3)],
        quality: evaluateCalibrationQuality(
          startPose: start,
          startPoseStability: 1,
          demonstrations: [_demo(1), _demo(2), _demo(3)],
        ),
        metadata: const CalibrationCaptureMetadata(
          capturedAtIso8601: '2026-01-01T00:00:00.000Z',
          cameraLensDirection: 'back',
          orientation: 'portraitUp',
          normalizerVersion: 'stage2-v1',
          deviceNote: 'test',
        ),
      ).toJson();

      expect(
        () => CustomPoseCalibration.fromJson({...calibration, 'version': 99}),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseCalibration.fromJson(
          {...calibration}..remove('startPose'),
        ),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseCalibration.fromJson({
          ...calibration,
          'demonstrations': [
            {'bad': 'data'},
          ],
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
      expect(
        () => CustomPoseCalibration.fromJson({
          ...calibration,
          'quality': {
            ...calibration['quality'] as Map<String, dynamic>,
            'averageValidFrameRatio': double.nan,
          },
        }),
        throwsA(isA<PoseDataFormatException>()),
      );
    });
  });

  group('PoseCalibrationFlow', () {
    test('validates movement name and progresses through summary', () {
      final flow = PoseCalibrationFlow(now: () => DateTime.utc(2026, 1, 1));

      expect(flow.setMovementName(''), isNotNull);
      expect(flow.setMovementName('Cross-body tap'), isNull);
      expect(flow.stage, TeachMovementStage.setup);
      flow.beginStartPose();
      flow.setStartPose(
        normalizer.normalize(neutralStandingPose()),
        stability: 1,
      );
      expect(flow.stage, TeachMovementStage.demonstration);
      flow.setDemonstration(_demo(1));
      expect(flow.nextDemonstrationIndex, 2);
      flow.setDemonstration(_demo(2));
      flow.setDemonstration(_demo(3));
      expect(flow.stage, TeachMovementStage.summary);
      expect(flow.buildCalibration(), isNotNull);
      flow.retryDemonstration(2);
      expect(flow.stage, TeachMovementStage.demonstration);
      expect(flow.nextDemonstrationIndex, 2);
    });

    test('does not expose publish behavior', () {
      final flow = PoseCalibrationFlow();
      expect(flow.buildCalibration(), isNull);
    });
  });
}

PoseDemonstration _demo(int index, {bool accepted = true}) {
  final pose = const PoseNormalizer().normalize(neutralStandingPose());
  return PoseDemonstration(
    index: index,
    frames: [
      PoseSequenceFrame(
        schemaVersion: normalizedPoseSchemaVersion,
        position: 0,
        elapsedMs: 0,
        pose: pose,
      ),
    ],
    durationMs: 900,
    processedFrameCount: 8,
    validFrameCount: accepted ? 8 : 2,
    validFrameRatio: accepted ? 1 : 0.25,
    averageVisibility: accepted ? 1 : 0.25,
    accepted: accepted,
    rejectionReason: accepted ? null : 'low_valid_frame_ratio',
  );
}
