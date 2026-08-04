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
        interrupted.addFrame(normalizer.normalize(neutralStandingPose()), start);
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

  group('SingleSessionTeachingCapture', () {
    test('set movement name captures start pose', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      expect(capture.setMovementName('Arms overhead'), isNull);
      expect(capture.stage, TeachMovementStage.startPose);

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }
      expect(capture.startPose, isNotNull);
      expect(capture.stage, TeachMovementStage.readyToRecord);
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
      expect(capture.message, contains('Record example 2'));
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
      for (var rep = 0; rep < 2; rep++) {
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
        capture.stopRecordingExampleAt(repStart.add(const Duration(milliseconds: 960)));
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
        capture.stopRecordingExampleAt(repStart.add(const Duration(milliseconds: 960)));
      }

      capture.buildWhenReady();
      expect(capture.stage, TeachMovementStage.learned);
      expect(capture.verifierSpec, isNotNull);
      expect(capture.verifierSpec?.movementName, 'Wave');
    });

    test('too-short manual recording is rejected', () {
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
      for (var i = 0; i < 2; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          start.add(Duration(milliseconds: 100 * i)),
        );
      }
      capture.stopRecordingExampleAt(start.add(const Duration(milliseconds: 200)));
      expect(capture.acceptedCount, 0);
      expect(capture.rejectedDemonstrations, isNotEmpty);
      expect(capture.message, contains('short'));
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
      capture.stopRecordingExampleAt(start.add(const Duration(milliseconds: 600)));
      expect(capture.acceptedCount, 0);
      expect(capture.rejectedDemonstrations, isNotEmpty);
      expect(capture.message, contains('clear movement'));
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

    test('resetToCapture keeps movement name and start pose', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Wave');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      final startPose = capture.startPose;
      expect(startPose, isNotNull);

      capture.startRecordingExample();
      for (var i = 0; i < 4; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose()),
          now.add(Duration(seconds: 1, milliseconds: 120 * i)),
        );
      }
      capture.stopRecordingExampleAt(now.add(const Duration(seconds: 2)));

      capture.resetToCapture();
      expect(capture.movementName, 'Wave');
      expect(capture.startPose, startPose);
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
        for (var i = 0; i < 6; i++) {
          capture.addFrame(
            normalizer.normalize(armsOverheadPose()),
            repStart.add(Duration(milliseconds: 120 * i)),
          );
        }
        capture.stopRecordingExampleAt(repStart.add(const Duration(milliseconds: 720)));
      }

      expect(capture.acceptedCount, 3);
      capture.removeLastAccepted();
      expect(capture.acceptedCount, 2);
      expect(capture.stage, TeachMovementStage.readyToRecord);
      expect(capture.movementName, 'Arms overhead');
    });

    test('can clear examples and keep the name and start pose', () {
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
          normalizer.normalize(armsOverheadPose()),
          start.add(Duration(milliseconds: 120 * i)),
        );
      }
      capture.stopRecordingExampleAt(start.add(const Duration(milliseconds: 720)));

      final startPose = capture.startPose;
      expect(capture.acceptedCount, 1);
      capture.clearExamples();
      expect(capture.acceptedCount, 0);
      expect(capture.movementName, 'Arms overhead');
      expect(capture.startPose, startPose);
      expect(capture.stage, TeachMovementStage.readyToRecord);
    });

    test('can reteach start pose without changing the name', () {
      var now = DateTime.utc(2026, 1, 1);
      final capture = SingleSessionTeachingCapture(now: () => now);
      capture.setMovementName('Arms overhead');

      for (var i = 0; i < 8; i++) {
        capture.addFrame(
          normalizer.normalize(neutralStandingPose()),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      expect(capture.startPose, isNotNull);
      capture.resetStartPose();
      expect(capture.startPose, isNull);
      expect(capture.movementName, 'Arms overhead');
      expect(capture.stage, TeachMovementStage.startPose);
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
      expect(capture.requiredExampleCount, 2);
      expect(capture.canLearn, isFalse);
      expect(capture.message, 'Record example 1');
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
      expect(capture.message, 'Recording example 1…');
      expect(capture.recordingProgress, 0.0);
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

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 6; i++) {
        capture.addFrame(
          normalizer.normalize(armsOverheadPose(dx: 0.01 * i)),
          start.add(Duration(milliseconds: 120 * i)),
        );
      }
      capture.stopRecordingExampleAt(start.add(const Duration(milliseconds: 720)));

      expect(capture.savedExampleCount, 1);
      expect(capture.canLearn, isFalse);
      expect(capture.lastExampleRejected, isFalse);
      expect(capture.canRecordExtraExample, isFalse);
      expect(capture.message, 'Record example 2');
    });

    test('after two saved examples can learn and allows a third', () {
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
      for (var rep = 0; rep < 2; rep++) {
        final repStart = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        capture.startRecordingExample();
        for (var i = 0; i < 6; i++) {
          capture.addFrame(
            normalizer.normalize(armsOverheadPose(dx: 0.01 * i)),
            repStart.add(Duration(milliseconds: 120 * i)),
          );
        }
        capture.stopRecordingExampleAt(repStart.add(const Duration(milliseconds: 720)));
      }

      expect(capture.savedExampleCount, 2);
      expect(capture.canLearn, isTrue);
      expect(capture.canRecordExtraExample, isTrue);
      expect(capture.message, 'Ready to learn');
    });

    test('a rejected example surfaces lastExampleRejected and asks to record again', () {
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
      capture.stopRecordingExampleAt(start.add(const Duration(milliseconds: 100)));

      expect(capture.savedExampleCount, 0);
      expect(capture.lastExampleRejected, isTrue);
      expect(capture.message, contains('Record it again'));
    });

    test('body not visible blocks recording and shows step prompt', () {
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
      expect(capture.canRecordNextExample, isFalse);
      expect(capture.message, contains('Step into frame'));

      capture.startRecordingExample();
      expect(capture.stage, TeachMovementStage.readyToRecord);
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
              },
            ),
          ),
          now.add(Duration(milliseconds: 100 * i)),
        );
      }

      expect(capture.stage, isNot(TeachMovementStage.readyToRecord));
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

      final start = now.add(const Duration(seconds: 1));
      capture.startRecordingExample();
      for (var i = 0; i < 5; i++) {
        capture.addFrame(
          normalizer.normalize(wavePose(dx: 0.01 * i)),
          start.add(Duration(milliseconds: 50 * i)),
        );
      }
      capture.stopRecordingExampleAt(start.add(const Duration(milliseconds: 250)));

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
      capture.stopRecordingExampleAt(start.add(const Duration(milliseconds: 400)));

      expect(capture.savedExampleCount, 0);
      expect(capture.lastExampleRejected, isTrue);
      expect(capture.message, contains('short'));
    });

    test('two short waves make Learn movement available', () {
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
      for (var rep = 0; rep < 2; rep++) {
        final repStart = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        capture.startRecordingExample();
        for (var i = 0; i < 5; i++) {
          capture.addFrame(
            normalizer.normalize(wavePose(dx: 0.01 * i)),
            repStart.add(Duration(milliseconds: 50 * i)),
          );
        }
        capture.stopRecordingExampleAt(
            repStart.add(const Duration(milliseconds: 250)));
      }

      expect(capture.savedExampleCount, 2);
      expect(capture.canLearn, isTrue);
    });

    test('markFrameMissing clears bodyVisible and prompts to step into frame', () {
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
      expect(capture.canRecordNextExample, isFalse);
      expect(capture.message, contains('Step into frame'));
    });

    test('one saved example shows Record example 2 and cannot learn', () {
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
          normalizer.normalize(wavePose(dx: 0.01 * i)),
          start.add(Duration(milliseconds: 50 * i)),
        );
      }
      capture.stopRecordingExampleAt(
          start.add(const Duration(milliseconds: 250)));

      expect(capture.savedExampleCount, 1);
      expect(capture.canLearn, isFalse);
      expect(capture.lastExampleRejected, isFalse);
      expect(capture.canRecordNextExample, isTrue);
      expect(capture.message, contains('Record example 2'));
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
          start.add(const Duration(milliseconds: 250)));

      expect(capture.savedExampleCount, 0);
      expect(capture.rejectedDemonstrations.length, 1);
      expect(capture.lastExampleRejected, isTrue);
      expect(capture.canLearn, isFalse);
      expect(capture.canRecordNextExample, isTrue);
      expect(capture.message, contains('Record it again'));
    });

    test('fixed clip records for 2 seconds and auto-saves a valid movement', () {
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

    test('fixed clip with no visible body rejects the example', () {
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

    test('quick wave inside a 2-second fixed clip can save', () {
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

    test('two fixed-clip examples enable Learn movement', () {
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
      for (var rep = 0; rep < 2; rep++) {
        final repStart = now.add(
          Duration(seconds: 1, milliseconds: rep * repGap.inMilliseconds),
        );
        capture.startRecordingExample();

        for (var i = 0; i < 10; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            repStart.add(Duration(milliseconds: 100 * i)),
          );
        }
        for (var i = 0; i < 10; i++) {
          capture.addFrame(
            normalizer.normalize(armsOverheadPose(dx: 0.02 * i)),
            repStart.add(Duration(milliseconds: 1000 + 50 * i)),
          );
        }
        for (var i = 0; i < 10; i++) {
          capture.addFrame(
            normalizer.normalize(neutralStandingPose()),
            repStart.add(Duration(milliseconds: 1500 + 50 * i)),
          );
        }

        capture.stopRecordingExampleAt(
            repStart.add(const Duration(seconds: 2)));
      }

      expect(capture.savedExampleCount, 2);
      expect(capture.canLearn, isTrue);
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


