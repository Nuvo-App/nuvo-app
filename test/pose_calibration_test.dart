import 'dart:convert';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/ai/custom_pose/normalized_pose.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_flow.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_models.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_quality.dart';

import 'package:nuvo/features/races/ai/custom_pose/pose_demonstration_capture.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_sequence_frame.dart';
import 'package:nuvo/features/races/ai/custom_pose/stable_pose_capture.dart';
import 'package:nuvo/features/races/presentation/custom_pose/pose_skeleton_overlay.dart';

import 'fixtures/pose_fixtures.dart';

DateTime _recordWaveExample(
  SingleSessionTeachingCapture capture,
  PoseNormalizer normalizer,
  DateTime start,
) {
  capture.startRecordingExample();
  final poses = [
    neutralStandingPose(),
    wavePose(dx: 0.05),
    wavePose(dx: 0.0),
    neutralStandingPose(),
  ];
  for (var i = 0; i < poses.length; i++) {
    capture.addFrame(
      normalizer.normalize(poses[i]),
      start.add(Duration(milliseconds: 50 * i)),
    );
  }
  final end = start.add(const Duration(milliseconds: 250));
  capture.stopRecordingExampleAt(end);
  return end;
}

void main() {
  const normalizer = PoseNormalizer();

  group('SkeletonFrameHold', () {
    test('holds last good pose briefly after one bad frame', () {
      final start = DateTime.utc(2026, 1, 1);
      final hold = SkeletonFrameHold(
        holdDuration: const Duration(milliseconds: 400),
      );
      final frame = neutralStandingPose(createdAt: start);

      hold.show(frame, start);
      final expired = hold.expire(start.add(const Duration(milliseconds: 250)));

      expect(expired, isFalse);
      expect(hold.frame, same(frame));
    });

    test('clears after no valid pose for hold window', () {
      final start = DateTime.utc(2026, 1, 1);
      final hold = SkeletonFrameHold(
        holdDuration: const Duration(milliseconds: 900),
      );
      hold.show(neutralStandingPose(createdAt: start), start);

      final expired = hold.expire(start.add(const Duration(milliseconds: 950)));

      expect(expired, isTrue);
      expect(hold.frame, isNull);
      expect(hold.lastVisibleAt, isNull);
    });

    test('maps skeleton coordinates through BoxFit cover crop', () {
      const point = NuvoPosePoint(x: 0.5, y: 0.5, z: 0, likelihood: 0.95);

      final mapped = PoseSkeletonCoordinateMapper.map(
        point: point,
        canvasSize: const Size(200, 400),
        sourceSize: const Size(100, 100),
        mirrorX: false,
      );

      expect(mapped.dx, closeTo(100, 0.001));
      expect(mapped.dy, closeTo(200, 0.001));
    });

    test('front camera x-coordinate mapping matches iOS preview mirroring', () {
      const point = NuvoPosePoint(x: 0.25, y: 0.5, z: 0, likelihood: 0.95);
      final mirrorX = PoseSkeletonPreviewTransform.shouldMirrorX(
        lensDirection: CameraLensDirection.front,
        platform: TargetPlatform.iOS,
      );

      final mapped = PoseSkeletonCoordinateMapper.map(
        point: point,
        canvasSize: const Size(200, 400),
        sourceSize: const Size(200, 400),
        mirrorX: mirrorX,
      );

      expect(mirrorX, isFalse);
      expect(mapped.dx, closeTo(50, 0.001));
      expect(mapped.dy, closeTo(200, 0.001));
    });

    test('front camera x-coordinate mapping mirrors Android preview', () {
      const point = NuvoPosePoint(x: 0.25, y: 0.5, z: 0, likelihood: 0.95);
      final mirrorX = PoseSkeletonPreviewTransform.shouldMirrorX(
        lensDirection: CameraLensDirection.front,
        platform: TargetPlatform.android,
      );

      final mapped = PoseSkeletonCoordinateMapper.map(
        point: point,
        canvasSize: const Size(200, 400),
        sourceSize: const Size(200, 400),
        mirrorX: mirrorX,
      );

      expect(mirrorX, isTrue);
      expect(mapped.dx, closeTo(150, 0.001));
      expect(mapped.dy, closeTo(200, 0.001));
    });

    test('back camera x-coordinate mapping is not mirrored', () {
      const point = NuvoPosePoint(x: 0.25, y: 0.5, z: 0, likelihood: 0.95);
      final mirrorX = PoseSkeletonPreviewTransform.shouldMirrorX(
        lensDirection: CameraLensDirection.back,
        platform: TargetPlatform.iOS,
      );

      final mapped = PoseSkeletonCoordinateMapper.map(
        point: point,
        canvasSize: const Size(200, 400),
        sourceSize: const Size(200, 400),
        mirrorX: mirrorX,
      );

      expect(mirrorX, isFalse);
      expect(mapped.dx, closeTo(50, 0.001));
      expect(mapped.dy, closeTo(200, 0.001));
    });

    test('left wrist paints on the visible left side in iOS front preview', () {
      const leftWrist = NuvoPosePoint(x: 0.25, y: 0.5, z: 0, likelihood: 0.95);
      final mirrorX = PoseSkeletonPreviewTransform.shouldMirrorX(
        lensDirection: CameraLensDirection.front,
        platform: TargetPlatform.iOS,
      );

      final mapped = PoseSkeletonCoordinateMapper.map(
        point: leftWrist,
        canvasSize: const Size(200, 400),
        sourceSize: const Size(200, 400),
        mirrorX: mirrorX,
      );

      expect(mapped.dx, lessThan(100));
    });

    test('skeleton and preview use the same BoxFit cover crop transform', () {
      const point = NuvoPosePoint(x: 0.25, y: 0.5, z: 0, likelihood: 0.95);
      const canvasSize = Size(200, 400);
      const sourceSize = Size(400, 200);

      final mapped = PoseSkeletonCoordinateMapper.map(
        point: point,
        canvasSize: canvasSize,
        sourceSize: sourceSize,
        mirrorX: false,
      );

      const scale = 400 / 200;
      const fittedWidth = 400 * scale;
      const cropX = (fittedWidth - 200) / 2;
      expect(mapped.dx, closeTo(0.25 * 400 * scale - cropX, 0.001));
      expect(mapped.dy, closeTo(0.5 * 200 * scale, 0.001));
    });
  });

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

    test('captures with the new default stability settings', () {
      final capture = StablePoseCapture();
      final start = DateTime.utc(2026);
      for (var i = 0; i < 6; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 100 * i)),
        );
      }
      final update = capture.addFrame(
        normalizer.normalize(neutralStandingPose()),
        start.add(const Duration(milliseconds: 600)),
      );

      expect(update.captured, isTrue);
      expect(update.pose, isNotNull);
      expect(update.stableFrameCount, greaterThanOrEqualTo(6));
    });
  });

  group('PoseDemonstrationCapture', () {
    test(
      'valid demonstration is accepted and sampled across the whole take',
      () {
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
        expect(demo.frames.first.elapsedMs, 0);
        expect(demo.frames.last.elapsedMs, 1320);
        expect(demo.validFrameRatio, greaterThan(0.6));
      },
    );

    test('finish returns monotonic frames after out-of-order processing', () {
      final capture = PoseDemonstrationCapture(index: 1);
      final start = DateTime.utc(2026);
      capture.start(start);
      final offsets = [0, 240, 120, 360, 600, 480];
      for (final offset in offsets) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose(dx: offset / 10000)),
          start.add(Duration(milliseconds: offset)),
        );
      }

      final demo = capture.finish(start.add(const Duration(milliseconds: 720)));

      expect(demo.accepted, isTrue);
      expect(_framesAreMonotonic(demo), isTrue);
      expect(
        demo.frames.map((frame) => frame.elapsedMs),
        orderedEquals([0, 120, 240, 360, 480, 600]),
      );
    });

    test('rejects too few frames, low valid ratio, and interruption', () {
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

      final interrupted = PoseDemonstrationCapture(index: 1)..start(start);
      interrupted.addFrame(normalizer.normalize(neutralStandingPose()), start);
      interrupted.interrupt();
      expect(
        interrupted
            .finish(start.add(const Duration(milliseconds: 900)))
            .rejectionReason,
        'capture_interrupted',
      );
    });
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

  group('SingleSessionTeachingCapture', () {
    test('set movement name puts flow into ready to record', () {
      final now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      expect(capture.setMovementName('Arms overhead'), isNull);
      expect(capture.stage, TeachMovementStage.readyToRecord);
      expect(capture.startPose, isNull);
      expect(capture.message, 'Show Nuvo the movement.');
      expect(capture.movementName, 'Arms overhead');
    });

    test('manual recording starts and stops an example', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Arms overhead');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }
      expect(capture.stage, TeachMovementStage.readyToRecord);

      now = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      expect(capture.stage, TeachMovementStage.recording);

      for (var i = 0; i < 2; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 120 * i)),
        );
      }
      for (var i = 0; i < 6; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          now.add(Duration(milliseconds: 120 * (2 + i))),
        );
      }

      now = now.add(const Duration(milliseconds: 960));
      capture.stopRecordingExample();
      expect(capture.stage, TeachMovementStage.readyToRecord);
      expect(capture.acceptedCount, 1);
      expect(capture.message, 'Example 1 saved');
    });

    test('recording stays active until the user stops it', () {
      final start = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => start);
      capture.setMovementName('Wave');
      capture.startRecordingExample();

      expect(capture.isRecording, isTrue);
    });

    test('two valid manual examples build a real verifier spec', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(
        now: () => now,
        buildDelay: Duration.zero,
      );
      capture.setMovementName('Arms overhead');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      const repGap = Duration(milliseconds: 1500);
      for (var rep = 0; rep < 3; rep++) {
        final repStart = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        capture.startRecordingExample();
        for (var i = 0; i < 2; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            repStart.add(Duration(milliseconds: 120 * i)),
          );
        }
        for (var i = 0; i < 6; i++) {
          capture.addFrame(
            normalizer.normalize(armsOverheadPose()),
            repStart.add(Duration(milliseconds: 120 * (2 + i))),
          );
        }
        capture.stopRecordingExampleAt(
          repStart.add(const Duration(milliseconds: 960)),
        );
      }

      capture.buildWhenReady();

      expect(capture.stage, TeachMovementStage.learned);
      expect(capture.verifierSpec, isNotNull);
      expect(capture.verifierSpec?.movementName, 'Arms overhead');
    });

    test('a wave-style movement can be captured and learned', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(
        now: () => now,
        buildDelay: Duration.zero,
      );
      capture.setCaptureDeviceInfo(
        cameraLensDirection: 'front',
        orientation: 'portraitUp',
        deviceNote: 'test_device',
      );
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      const repGap = Duration(milliseconds: 1500);
      for (var rep = 0; rep < 3; rep++) {
        final repStart = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        capture.startRecordingExample();
        for (var i = 0; i < 2; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            repStart.add(Duration(milliseconds: 120 * i)),
          );
        }
        for (var i = 0; i < 6; i++) {
          capture.addFrame(
            normalizer.normalize(wavePose()),
            repStart.add(Duration(milliseconds: 120 * (2 + i))),
          );
        }
        capture.stopRecordingExampleAt(
          repStart.add(const Duration(milliseconds: 960)),
        );
      }

      capture.buildWhenReady();
      expect(capture.stage, TeachMovementStage.learned);
      expect(capture.verifierSpec, isNotNull);
      expect(capture.verifierSpec?.movementName, 'Wave');
      final report = capture.debugReport();
      expect(report['cameraLensDirection'], 'front');
      expect(report['exampleCount'], 3);
      expect(report['activeFeatureIds'], isNotEmpty);
      expect(report['topMovingFeaturesByAmplitude'], isNotEmpty);
      expect(report['featureCoverageAcrossExamples'], isNotEmpty);
      expect(
        report['waveBodyPartCoverage'],
        containsPair('requiresAnkles', isFalse),
      );
    });

    test(
      'three accepted waves with one out-of-order arrival stay structurally valid',
      () {
        var now = DateTime.utc(2026, 1, 1);
        final capture = SingleSessionTeachingCapture(
          now: () => now,
          buildDelay: Duration.zero,
        );
        capture.setMovementName('Wave');

        for (var i = 0; i < 8; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            now.add(Duration(milliseconds: 100 * i)),
          );
        }

        const repGap = Duration(milliseconds: 1500);
        for (var rep = 0; rep < 3; rep++) {
          final repStart = now.add(
            Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
          );
          capture.startRecordingExample();
          final poses = [
            normalizer.normalize(neutralStandingPose()),
            normalizer.normalize(neutralStandingPose()),
            normalizer.normalize(wavePose()),
            normalizer.normalize(wavePose(dx: 0.05)),
            normalizer.normalize(wavePose()),
            normalizer.normalize(wavePose(dx: 0.05)),
            normalizer.normalize(neutralStandingPose()),
            normalizer.normalize(neutralStandingPose()),
          ];
          final order = rep == 2
              ? [0, 1, 3, 2, 4, 5, 6, 7]
              : [0, 1, 2, 3, 4, 5, 6, 7];
          for (final index in order) {
            capture.addFrame(
              poses[index],
              repStart.add(Duration(milliseconds: 120 * index)),
            );
          }
          capture.stopRecordingExampleAt(
            repStart.add(const Duration(milliseconds: 960)),
          );
        }

        expect(capture.acceptedDemonstrations, hasLength(3));
        expect(
          capture.acceptedDemonstrations.every(_framesAreMonotonic),
          isTrue,
        );

        capture.buildWhenReady();
        expect(capture.lastBuildFailure, isNot('demo_3_non_monotonic_frames'));
      },
    );

    test('manual recording with too few frames is rejected', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Arms overhead');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      now = start;
      capture.startRecordingExample();
      for (var i = 0; i < 2; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          start.add(Duration(milliseconds: 100 * i)),
        );
      }
      capture.stopRecordingExampleAt(
        start.add(const Duration(milliseconds: 150)),
      );
      expect(capture.acceptedCount, 0);
      expect(capture.rejectedDemonstrations, isNotEmpty);
      expect(capture.lastRejection, 'too_few_processed_frames');
      expect(capture.message, contains('trouble reading'));
    });

    test('static manual recording is rejected', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Arms overhead');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 6; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 100 * i)),
        );
      }
      capture.stopRecordingExampleAt(
        start.add(const Duration(milliseconds: 600)),
      );
      expect(capture.acceptedCount, 0);
      expect(capture.rejectedDemonstrations, isNotEmpty);
      expect(capture.message, contains('did not move enough'));
    });

    test('name persists through restart', () {
      final capture = SingleSessionTeachingCapture(
        now: () => DateTime.utc(2026, 1, 1),
      );
      capture.setMovementName('Wave');
      expect(capture.movementName, 'Wave');
      capture.restart();
      expect(capture.movementName, 'Wave');
      expect(capture.stage, isNot(TeachMovementStage.name));
    });

    test('resetToCapture keeps movement name and resets start pose', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 4; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          start.add(Duration(milliseconds: 120 * i)),
        );
      }
      capture.stopRecordingExampleAt(start.add(const Duration(seconds: 1)));

      expect(capture.startPose, isNotNull);

      capture.resetToCapture();
      expect(capture.movementName, 'Wave');
      expect(capture.startPose, isNull);
      expect(capture.acceptedDemonstrations, isEmpty);
      expect(capture.stage, TeachMovementStage.readyToRecord);
    });

    test('can remove the last accepted example and continue', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(
        now: () => now,
        buildDelay: Duration.zero,
      );
      capture.setMovementName('Arms overhead');

      const repGap = Duration(milliseconds: 1500);
      for (var rep = 0; rep < 3; rep++) {
        now = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        capture.startRecordingExample();
        for (var i = 0; i < 2; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            now.add(Duration(milliseconds: 120 * i)),
          );
        }
        for (var i = 0; i < 6; i++) {
          capture.addFrame(
            normalizer.normalize(armsOverheadPose()),
            now.add(Duration(milliseconds: 120 * (2 + i))),
          );
        }
        capture.stopRecordingExampleAt(
          now.add(const Duration(milliseconds: 960)),
        );
        now = now.add(const Duration(milliseconds: 960));
      }

      expect(capture.acceptedCount, 3);
      capture.removeLastAccepted();
      expect(capture.acceptedCount, 2);
      expect(capture.stage, TeachMovementStage.readyToRecord);
      expect(capture.movementName, 'Arms overhead');
    });

    test('can clear examples and keep the name but reset start pose', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Arms overhead');

      now = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 2; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 120 * i)),
        );
      }
      for (var i = 0; i < 6; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          now.add(Duration(milliseconds: 120 * (2 + i))),
        );
      }
      capture.stopRecordingExampleAt(
        now.add(const Duration(milliseconds: 960)),
      );

      expect(capture.startPose, isNotNull);
      expect(capture.acceptedCount, 1);
      capture.clearExamples();
      expect(capture.acceptedCount, 0);
      expect(capture.movementName, 'Arms overhead');
      expect(capture.startPose, isNull);
      expect(capture.stage, TeachMovementStage.readyToRecord);
    });

    test('can reteach start pose without changing the name', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Arms overhead');

      now = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 2; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 120 * i)),
        );
      }
      for (var i = 0; i < 6; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          now.add(Duration(milliseconds: 120 * (2 + i))),
        );
      }
      capture.stopRecordingExampleAt(
        now.add(const Duration(milliseconds: 960)),
      );

      expect(capture.startPose, isNotNull);
      capture.resetStartPose();
      expect(capture.startPose, isNull);
      expect(capture.movementName, 'Arms overhead');
      expect(capture.stage, TeachMovementStage.readyToRecord);
    });

    test('too few processed frames shows a friendly message', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      now = start;
      capture.startRecordingExample();
      for (var i = 0; i < 2; i++) {
        capture.addFrame(
          normalizer.normalize(wavePose()),
          start.add(Duration(milliseconds: 120 * i)),
        );
      }
      capture.stopRecordingExampleAt(start.add(const Duration(seconds: 1)));

      expect(capture.acceptedCount, 0);
      expect(capture.lastExampleRejected, isTrue);
      expect(capture.message, contains('trouble'));
    });

    test('start pose is computed from the first valid frame window', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      final start = now.add(const Duration(seconds: 1));
      now = start;
      capture.startRecordingExample();
      for (var i = 0; i < 4; i++) {
        capture.addFrame(
          normalizer.normalize(wavePose()),
          start.add(Duration(milliseconds: 120 * i)),
        );
      }
      for (var i = 0; i < 6; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 120 * (4 + i))),
        );
      }
      capture.stopRecordingExampleAt(start.add(const Duration(seconds: 1)));

      expect(capture.startPose, isNotNull);
      expect(capture.rejectedDemonstrations, isEmpty);
      expect(capture.acceptedCount, 1);
    });
  });

  group('SingleSessionTeachingCapture UI state', () {
    test('initially shows Record example 1 and cannot learn', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      expect(capture.stage, TeachMovementStage.readyToRecord);
      expect(capture.savedExampleCount, 0);
      expect(capture.requiredExampleCount, 3);
      expect(capture.canLearn, isFalse);
      expect(capture.message, 'Show Nuvo the movement.');
    });

    test('while recording shows Recording example 1… and progress', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      capture.startRecordingExample();
      expect(capture.isRecording, isTrue);
      expect(capture.message, 'Recording…');
    });

    test('after one saved example cannot learn and prompts for example 2', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      now = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 2; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 120 * i)),
        );
      }
      for (var i = 0; i < 6; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose(dx: 0.01 * i)),
          now.add(Duration(milliseconds: 120 * (2 + i))),
        );
      }
      capture.stopRecordingExampleAt(
        now.add(const Duration(milliseconds: 960)),
      );

      expect(capture.savedExampleCount, 1);
      expect(capture.canLearn, isFalse);
      expect(capture.lastExampleRejected, isFalse);
      expect(capture.canRecordExtraExample, isFalse);
      expect(capture.message, 'Example 1 saved');
    });

    test('after two saved examples cannot learn and prompts for a third', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      const repGap = Duration(milliseconds: 1500);
      for (var rep = 0; rep < 2; rep++) {
        now = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        capture.startRecordingExample();
        for (var i = 0; i < 2; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            now.add(Duration(milliseconds: 120 * i)),
          );
        }
        for (var i = 0; i < 6; i++) {
          capture.addFrame(
            normalizer.normalize(armsOverheadPose(dx: 0.01 * i)),
            now.add(Duration(milliseconds: 120 * (2 + i))),
          );
        }
        capture.stopRecordingExampleAt(
          now.add(const Duration(milliseconds: 960)),
        );
        now = now.add(const Duration(milliseconds: 960));
      }

      expect(capture.savedExampleCount, 2);
      expect(capture.canLearn, isFalse);
      expect(capture.canRecordNextExample, isTrue);
      expect(capture.canRecordExtraExample, isFalse);
      expect(capture.message, 'Example 2 saved');
    });

    test(
      'a rejected example surfaces lastExampleRejected and asks to record again',
      () {
        var now = DateTime.utc(2026, 1, 1);
        final capture = SingleSessionTeachingCapture(now: () => now);
        capture.setMovementName('Wave');

        for (var i = 0; i < 8; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            now.add(Duration(milliseconds: 100 * i)),
          );
        }

        final start = now.add(const Duration(seconds: 1));
        capture.startRecordingExample();
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          start.add(const Duration(milliseconds: 50)),
        );
        capture.stopRecordingExampleAt(
          start.add(const Duration(milliseconds: 100)),
        );

        expect(capture.savedExampleCount, 0);
        expect(capture.lastExampleRejected, isTrue);
        expect(capture.message, contains('Record it again'));
      },
    );

    test('body not visible no longer blocks recording', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      expect(capture.bodyVisible, isTrue);
      expect(capture.canRecordNextExample, isTrue);

      for (var i = 0; i < 5; i++) {
        capture.addFrame(
          normalizer.normalize(
            neutralStandingPose(
              likelihoods: const {
                'nose': 0.0,
                'leftShoulder': 0.0,
                'rightShoulder': 0.0,
                'leftElbow': 0.0,
                'rightElbow': 0.0,
                'leftWrist': 0.0,
                'rightWrist': 0.0,
                'leftHip': 0.0,
                'rightHip': 0.0,
                'leftKnee': 0.0,
                'rightKnee': 0.0,
                'leftAnkle': 0.0,
                'rightAnkle': 0.0,
              },
            ),
          ),
          now.add(Duration(seconds: 1, milliseconds: 100 * i)),
        );
      }

      expect(capture.bodyVisible, isFalse);
      expect(capture.canRecordNextExample, isTrue);
      expect(capture.message, 'Show Nuvo the movement.');

      capture.startRecordingExample();
      expect(capture.stage, TeachMovementStage.recording);
    });

    test('partial body is not treated as a visible body', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(
            neutralStandingPose(
              missing: const {
                'leftShoulder',
                'rightShoulder',
                'leftElbow',
                'rightElbow',
                'leftWrist',
                'rightWrist',
                'leftHip',
                'rightHip',
                'leftKnee',
                'rightKnee',
                'leftAnkle',
                'rightAnkle',
              },
            ),
          ),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      expect(capture.stage, TeachMovementStage.readyToRecord);
      expect(capture.bodyVisible, isFalse);
    });

    test('short valid wave-style example is accepted', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      now = now.add(const Duration(seconds: 1));
      now = _recordWaveExample(capture, normalizer, now);

      expect(capture.savedExampleCount, 1);
      expect(capture.lastExampleRejected, isFalse);
      expect(capture.canLearn, isFalse);
    });

    test('recording with no valid pose frames is rejected', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 10; i++) {
        capture.addFrame(
          normalizer.normalize(
            neutralStandingPose(
              likelihoods: const {
                'nose': 0.0,
                'leftShoulder': 0.0,
                'rightShoulder': 0.0,
                'leftElbow': 0.0,
                'rightElbow': 0.0,
                'leftWrist': 0.0,
                'rightWrist': 0.0,
                'leftHip': 0.0,
                'rightHip': 0.0,
                'leftKnee': 0.0,
                'rightKnee': 0.0,
                'leftAnkle': 0.0,
                'rightAnkle': 0.0,
              },
            ),
          ),
          start.add(Duration(milliseconds: 40 * i)),
        );
      }
      capture.stopRecordingExampleAt(
        start.add(const Duration(milliseconds: 400)),
      );

      expect(capture.savedExampleCount, 0);
      expect(capture.lastExampleRejected, isTrue);
      expect(capture.message, contains('couldn\'t read'));
    });

    test('three short waves make Learn movement available', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      const repGap = Duration(milliseconds: 1500);
      for (var rep = 0; rep < 3; rep++) {
        now = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        now = _recordWaveExample(capture, normalizer, now);
      }

      expect(capture.savedExampleCount, 3);
      expect(capture.canLearn, isTrue);
    });

    test('markFrameMissing clears bodyVisible and keeps recording prompt', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      expect(capture.bodyVisible, isTrue);
      expect(capture.canRecordNextExample, isTrue);

      capture.markFrameMissing();

      expect(capture.bodyVisible, isFalse);
      expect(capture.canRecordNextExample, isTrue);
      expect(capture.message, 'Show Nuvo the movement.');
    });

    test('one saved example shows saved copy and cannot learn', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      now = now.add(const Duration(seconds: 1));
      now = _recordWaveExample(capture, normalizer, now);

      expect(capture.savedExampleCount, 1);
      expect(capture.canLearn, isFalse);
      expect(capture.lastExampleRejected, isFalse);
      expect(capture.canRecordNextExample, isTrue);
      expect(capture.message, 'Example 1 saved');
    });

    test('rejected example shows Record again and cannot learn', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 5; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 50 * i)),
        );
      }
      capture.stopRecordingExampleAt(
        start.add(const Duration(milliseconds: 250)),
      );

      expect(capture.savedExampleCount, 0);
      expect(capture.rejectedDemonstrations.length, 1);
      expect(capture.lastExampleRejected, isTrue);
      expect(capture.canLearn, isFalse);
      expect(capture.canRecordNextExample, isTrue);
      expect(capture.message, contains('Record it again'));
    });

    test('manual Stop saves a valid movement after enough frames', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Arms overhead');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();

      // Hold start, then lift arms for ~1 second, then hold.
      for (var i = 0; i < 10; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 100 * i)),
        );
      }
      for (var i = 0; i < 10; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose(dx: 0.02 * i)),
          start.add(Duration(milliseconds: 1000 + 50 * i)),
        );
      }
      for (var i = 0; i < 10; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 1500 + 50 * i)),
        );
      }

      capture.stopRecordingExampleAt(start.add(const Duration(seconds: 2)));

      expect(capture.savedExampleCount, 1);
      expect(capture.lastExampleRejected, isFalse);
    });

    test('manual Stop with no visible body rejects the example', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();

      for (var i = 0; i < 30; i++) {
        capture.addFrame(
          normalizer.normalize(
            neutralStandingPose(
              likelihoods: const {
                'nose': 0.0,
                'leftShoulder': 0.0,
                'rightShoulder': 0.0,
                'leftElbow': 0.0,
                'rightElbow': 0.0,
                'leftWrist': 0.0,
                'rightWrist': 0.0,
                'leftHip': 0.0,
                'rightHip': 0.0,
                'leftKnee': 0.0,
                'rightKnee': 0.0,
                'leftAnkle': 0.0,
                'rightAnkle': 0.0,
              },
            ),
          ),
          start.add(Duration(milliseconds: 67 * i)),
        );
      }

      capture.stopRecordingExampleAt(start.add(const Duration(seconds: 2)));

      expect(capture.savedExampleCount, 0);
      expect(capture.lastExampleRejected, isTrue);
    });

    test('quick wave can save when the user taps Stop', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();

      for (var i = 0; i < 10; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 100 * i)),
        );
      }
      for (var i = 0; i < 5; i++) {
        capture.addFrame(
          normalizer.normalize(wavePose(dx: 0.05 * i)),
          start.add(Duration(milliseconds: 1000 + 50 * i)),
        );
      }
      for (var i = 0; i < 10; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 1250 + 125 * i)),
        );
      }

      capture.stopRecordingExampleAt(start.add(const Duration(seconds: 2)));

      expect(capture.savedExampleCount, 1);
      expect(capture.lastExampleRejected, isFalse);
    });

    test('three manually finished examples enable Learn movement', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Arms overhead');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      const repGap = Duration(milliseconds: 2500);
      for (var rep = 0; rep < 3; rep++) {
        now = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        capture.startRecordingExample();

        for (var i = 0; i < 10; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            now.add(Duration(milliseconds: 100 * i)),
          );
        }
        for (var i = 0; i < 10; i++) {
          capture.addFrame(
            normalizer.normalize(armsOverheadPose(dx: 0.02 * i)),
            now.add(Duration(milliseconds: 1000 + 50 * i)),
          );
        }
        for (var i = 0; i < 10; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            now.add(Duration(milliseconds: 1500 + 50 * i)),
          );
        }

        capture.stopRecordingExampleAt(now.add(const Duration(seconds: 2)));
        now = now.add(const Duration(seconds: 2));
      }

      expect(capture.savedExampleCount, 3);
      expect(capture.canLearn, isTrue);
    });

    test('short quick wave is accepted as a valid example', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      final wavePoses = [
        neutralStandingPose(),
        wavePose(dx: 0.05),
        wavePose(dx: 0.0),
        neutralStandingPose(),
      ];
      for (var i = 0; i < wavePoses.length; i++) {
        capture.addFrame(
          normalizer.normalize(wavePoses[i]),
          start.add(Duration(milliseconds: 50 * i)),
        );
      }
      capture.stopRecordingExampleAt(
        start.add(const Duration(milliseconds: 250)),
      );

      expect(capture.savedExampleCount, 1);
      expect(capture.lastExampleRejected, isFalse);
    });

    test('upper body only is treated as visible', () {
      final capture = SingleSessionTeachingCapture();
      final upperBody = normalizer.normalize(
        neutralStandingPose(
          missing: const {
            'leftHip',
            'rightHip',
            'leftKnee',
            'rightKnee',
            'leftAnkle',
            'rightAnkle',
          },
        ),
      );
      final fullBody = normalizer.normalize(neutralStandingPose());
      final empty = normalizer.normalize(
        neutralStandingPose(
          missing: const {
            'nose',
            'leftShoulder',
            'rightShoulder',
            'leftElbow',
            'rightElbow',
            'leftWrist',
            'rightWrist',
            'leftHip',
            'rightHip',
            'leftKnee',
            'rightKnee',
            'leftAnkle',
            'rightAnkle',
          },
        ),
      );
      final oneRandom = normalizer.normalize(
        neutralStandingPose(
          missing: const {
            'leftShoulder',
            'rightShoulder',
            'leftElbow',
            'rightElbow',
            'leftWrist',
            'rightWrist',
            'leftHip',
            'rightHip',
            'leftKnee',
            'rightKnee',
            'leftAnkle',
            'rightAnkle',
          },
        ),
      );

      expect(capture.isBodyVisiblePose(upperBody), isTrue);
      expect(capture.isBodyVisiblePose(fullBody), isTrue);
      expect(capture.isBodyVisiblePose(empty), isFalse);
      expect(capture.isBodyVisiblePose(oneRandom), isFalse);
    });

    test('body visibility does not flicker off after one bad frame', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      final upperBody = normalizer.normalize(
        neutralStandingPose(
          missing: const {
            'leftHip',
            'rightHip',
            'leftKnee',
            'rightKnee',
            'leftAnkle',
            'rightAnkle',
          },
        ),
      );
      final empty = normalizer.normalize(
        neutralStandingPose(
          missing: const {
            'nose',
            'leftShoulder',
            'rightShoulder',
            'leftElbow',
            'rightElbow',
            'leftWrist',
            'rightWrist',
            'leftHip',
            'rightHip',
            'leftKnee',
            'rightKnee',
            'leftAnkle',
            'rightAnkle',
          },
        ),
      );

      for (var i = 0; i < 2; i++) {
        capture.addFrame(upperBody, now.add(Duration(milliseconds: 100 * i)));
      }
      expect(capture.bodyVisible, isTrue);

      capture.addFrame(empty, now.add(const Duration(milliseconds: 300)));
      expect(capture.bodyVisible, isTrue);

      capture.addFrame(empty, now.add(const Duration(milliseconds: 400)));
      expect(capture.bodyVisible, isFalse);
    });

    test('upper-body only can start recording', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      final upperBody = normalizer.normalize(
        neutralStandingPose(
          missing: const {
            'leftHip',
            'rightHip',
            'leftKnee',
            'rightKnee',
            'leftAnkle',
            'rightAnkle',
          },
        ),
      );
      for (var i = 0; i < 8; i++) {
        capture.addFrame(upperBody, now.add(Duration(milliseconds: 100 * i)));
      }

      expect(capture.bodyVisible, isTrue);
      now = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      capture.addFrame(upperBody, now);
      expect(capture.startPose, isNotNull);
      expect(capture.isRecording, isTrue);
    });

    test('static full-body clip is rejected', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 30; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          start.add(Duration(milliseconds: 67 * i)),
        );
      }
      capture.stopRecordingExampleAt(start.add(const Duration(seconds: 2)));

      expect(capture.savedExampleCount, 0);
      expect(capture.lastExampleRejected, isTrue);
    });

    test('lower body only is treated as visible', () {
      final capture = SingleSessionTeachingCapture();

      final lowerBody = normalizer.normalize(
        neutralStandingPose(
          missing: const {
            'nose',
            'leftShoulder',
            'rightShoulder',
            'leftElbow',
            'rightElbow',
            'leftWrist',
            'rightWrist',
          },
        ),
      );
      final empty = normalizer.normalize(
        neutralStandingPose(
          missing: const {
            'nose',
            'leftShoulder',
            'rightShoulder',
            'leftElbow',
            'rightElbow',
            'leftWrist',
            'rightWrist',
            'leftHip',
            'rightHip',
            'leftKnee',
            'rightKnee',
            'leftAnkle',
            'rightAnkle',
          },
        ),
      );

      expect(capture.isBodyVisiblePose(lowerBody), isTrue);
      expect(capture.isBodyVisiblePose(empty), isFalse);
    });

    test(
      'short wave can be recorded and learned with upper-body visibility',
      () {
        var now = DateTime.utc(2026, 1, 1);
        final capture = SingleSessionTeachingCapture(now: () => now);
        capture.setMovementName('Wave');

        final upperBody = normalizer.normalize(
          neutralStandingPose(
            missing: const {
              'leftHip',
              'rightHip',
              'leftKnee',
              'rightKnee',
              'leftAnkle',
              'rightAnkle',
            },
          ),
        );
        for (var i = 0; i < 8; i++) {
          capture.addFrame(upperBody, now.add(Duration(milliseconds: 100 * i)));
        }

        final start = now.add(const Duration(seconds: 1));
        capture.startRecordingExample();
        final wavePoses = [
          neutralStandingPose(
            missing: const {
              'leftHip',
              'rightHip',
              'leftKnee',
              'rightKnee',
              'leftAnkle',
              'rightAnkle',
            },
          ),
          wavePose(dx: 0.05),
          wavePose(dx: 0.0),
          neutralStandingPose(
            missing: const {
              'leftHip',
              'rightHip',
              'leftKnee',
              'rightKnee',
              'leftAnkle',
              'rightAnkle',
            },
          ),
        ];
        for (var i = 0; i < wavePoses.length; i++) {
          capture.addFrame(
            normalizer.normalize(wavePoses[i]),
            start.add(Duration(milliseconds: 50 * i)),
          );
        }
        capture.stopRecordingExampleAt(
          start.add(const Duration(milliseconds: 250)),
        );

        expect(capture.savedExampleCount, 1);
        expect(capture.lastExampleRejected, isFalse);
      },
    );

    test('one continuous recording learns three repeated movements', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(
        now: () => now,
        buildDelay: Duration.zero,
      );
      capture.setMovementName('Arms overhead');

      final frames = <NuvoPoseFrame>[
        for (var i = 0; i < 4; i++) neutralStandingPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
      ];
      capture.startContinuousRecording();
      expect(capture.stage, TeachMovementStage.recording);

      for (var i = 0; i < frames.length; i++) {
        capture.addFrame(
          normalizer.normalize(frames[i]),
          now.add(Duration(milliseconds: 120 * i)),
        );
      }

      capture.stopContinuousRecordingAt(
        now.add(Duration(milliseconds: 120 * frames.length)),
      );

      expect(capture.acceptedCount, 3);
      expect(capture.stage, TeachMovementStage.learned);
      expect(capture.verifierSpec, isNotNull);
      expect(capture.verifierSpec?.movementName, 'Arms overhead');
      final report = capture.debugReport();
      expect(report['continuousRecording'], isTrue);
      expect(report['detectedRepetitionCount'], 3);
    });

    test(
      'continuous recording asks for another recording when fewer than two repetitions are found',
      () {
        var now = DateTime.utc(2026, 1, 1);
        final capture = SingleSessionTeachingCapture(now: () => now);
        capture.setMovementName('Arms overhead');

        final frames = <NuvoPoseFrame>[
          for (var i = 0; i < 4; i++) neutralStandingPose(),
          neutralStandingPose(),
          neutralStandingPose(),
          armsOverheadPose(),
          armsOverheadPose(),
          neutralStandingPose(),
          neutralStandingPose(),
        ];
        capture.startContinuousRecording();

        for (var i = 0; i < frames.length; i++) {
          capture.addFrame(
            normalizer.normalize(frames[i]),
            now.add(Duration(milliseconds: 120 * i)),
          );
        }

        capture.stopContinuousRecordingAt(
          now.add(Duration(milliseconds: 120 * frames.length)),
        );

        expect(capture.acceptedCount, 1);
        expect(capture.stage, TeachMovementStage.readyToRecord);
        expect(capture.verifierSpec, isNull);
        expect(capture.message, 'Show me that once more.');
        final report = capture.debugReport();
        expect(report['detectedRepetitionCount'], 1);
      },
    );

    test('three separate recordings build automatically after the third', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(
        now: () => now,
        buildDelay: Duration.zero,
      );
      capture.setMovementName('Arms overhead');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }
      expect(capture.acceptedCount, 0);
      expect(capture.stage, TeachMovementStage.readyToRecord);

      for (var rep = 0; rep < 3; rep++) {
        now = now.add(Duration(seconds: 1, milliseconds: rep * 1500));
        capture.startRecordingExample();
        expect(capture.stage, TeachMovementStage.recording);
        for (var i = 0; i < 2; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            now.add(Duration(milliseconds: 120 * i)),
          );
        }
        for (var i = 0; i < 6; i++) {
          capture.addFrame(
            normalizer.normalize(armsOverheadPose(dx: 0.01 * i)),
            now.add(Duration(milliseconds: 120 * (2 + i))),
          );
        }
        capture.stopRecordingExampleAt(
          now.add(const Duration(milliseconds: 960)),
        );

        if (rep < 2) {
          expect(capture.acceptedCount, rep + 1);
          expect(capture.stage, TeachMovementStage.readyToRecord);
        }
        now = now.add(const Duration(milliseconds: 960));
      }

      expect(capture.acceptedCount, 3);
      expect(capture.canLearn, isTrue);
      capture.buildWhenReady();
      expect(capture.stage, TeachMovementStage.learned);
      expect(capture.verifierSpec, isNotNull);
      expect(capture.verifierSpec?.movementName, 'Arms overhead');
    });

    test(
      'a rejected recording does not erase previously accepted recordings',
      () {
        var now = DateTime.utc(2026, 1, 1);
        final capture = SingleSessionTeachingCapture(now: () => now);
        capture.setMovementName('Arms overhead');

        for (var i = 0; i < 8; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            now.add(Duration(milliseconds: 100 * i)),
          );
        }

        now = now.add(const Duration(seconds: 1));
        now = _recordWaveExample(capture, normalizer, now);
        expect(capture.acceptedCount, 1);
        expect(capture.stage, TeachMovementStage.readyToRecord);

        now = now.add(const Duration(seconds: 1));
        capture.startRecordingExample();
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          now.add(const Duration(milliseconds: 50)),
        );
        capture.stopRecordingExampleAt(
          now.add(const Duration(milliseconds: 100)),
        );

        expect(capture.acceptedCount, 1);
        expect(capture.stage, TeachMovementStage.readyToRecord);
        expect(capture.lastExampleRejected, isTrue);

        now = now.add(const Duration(seconds: 1));
        now = _recordWaveExample(capture, normalizer, now);
        expect(capture.acceptedCount, 2);
        expect(capture.stage, TeachMovementStage.readyToRecord);
      },
    );
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

bool _framesAreMonotonic(PoseDemonstration demo) {
  var previousElapsed = -1;
  var previousPosition = -1.0;
  for (final frame in demo.frames) {
    if (frame.elapsedMs < previousElapsed ||
        frame.position < previousPosition) {
      return false;
    }
    previousElapsed = frame.elapsedMs;
    previousPosition = frame.position;
  }
  return true;
}
