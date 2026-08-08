import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/normalized_pose.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_repetition_splitter.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_sequence_frame.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'fixtures/pose_fixtures.dart';

List<PoseSequenceFrame> _frames(List<NuvoPoseFrame> frames) {
  final normalizer = const PoseNormalizer();
  return List.generate(
    frames.length,
    (index) => PoseSequenceFrame(
      schemaVersion: normalizedPoseSchemaVersion,
      position: frames.length == 1 ? 0.0 : index / (frames.length - 1),
      elapsedMs: index * 120,
      pose: normalizer.normalize(frames[index]),
    ),
    growable: false,
  );
}

void main() {
  const splitter = PoseRepetitionSplitter();
  const normalizer = PoseNormalizer();

  group('PoseRepetitionSplitter', () {
    test('three clear repeated movements', () {
      final start = normalizer.normalize(neutralStandingPose());
      final frames = _frames([
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
      ]);

      final demos = splitter.split(frames: frames, startPose: start);

      expect(demos.length, 3);
      for (final demo in demos) {
        expect(demo.accepted, isTrue);
        expect(demo.rejectionReason, isNull);
        expect(demo.frames.length, greaterThanOrEqualTo(4));
        expect(demo.frames.first.position, 0.0);
        expect(demo.frames.last.position, 1.0);
        expect(demo.frames.first.elapsedMs, 0);
        _expectMonotonic(demo.frames);
      }
    });

    test('more than three repetitions returns at most three', () {
      final start = normalizer.normalize(neutralStandingPose());
      final frames = _frames([
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
      ]);

      final demos = splitter.split(frames: frames, startPose: start);

      expect(demos.length, 3);
    });

    test('only one complete repetition', () {
      final start = normalizer.normalize(neutralStandingPose());
      final frames = _frames([
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
      ]);

      final demos = splitter.split(frames: frames, startPose: start);

      expect(demos.length, 1);
      expect(demos.first.accepted, isTrue);
      expect(demos.first.frames.length, greaterThanOrEqualTo(4));
    });

    test('incomplete final repetition is ignored', () {
      final start = normalizer.normalize(neutralStandingPose());
      final frames = _frames([
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
        neutralStandingPose(),
        armsOverheadPose(),
        armsOverheadPose(),
        neutralStandingPose(),
      ]);

      final demos = splitter.split(frames: frames, startPose: start);

      expect(demos.length, 2);
    });

    test('no meaningful movement returns empty list', () {
      final start = normalizer.normalize(neutralStandingPose());
      final frames = _frames([
        for (var i = 0; i < 8; i++) neutralStandingPose(),
      ]);

      final demos = splitter.split(frames: frames, startPose: start);

      expect(demos, isEmpty);
    });
  });
}

void _expectMonotonic(List<PoseSequenceFrame> frames) {
  for (var i = 1; i < frames.length; i++) {
    expect(
      frames[i].position >= frames[i - 1].position,
      isTrue,
      reason: 'positions must be monotonic',
    );
    expect(
      frames[i].elapsedMs >= frames[i - 1].elapsedMs,
      isTrue,
      reason: 'elapsedMs must be monotonic',
    );
  }
}
