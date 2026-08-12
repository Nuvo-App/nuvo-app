import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/pose_landmark_smoother.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

NuvoPoseFrame _frame(double x, DateTime at) => NuvoPoseFrame(
  points: {'leftShoulder': NuvoPosePoint(x: x, y: 0.4, z: 0, likelihood: 0.95)},
  imageWidth: 1000,
  imageHeight: 1000,
  createdAt: at,
);

void main() {
  test('smooths small landmark jitter while preserving confidence', () {
    final smoother = PoseLandmarkSmoother();
    final start = DateTime.utc(2026, 1, 1);

    smoother.smooth(_frame(0.40, start));
    final output = smoother.smooth(
      _frame(0.44, start.add(const Duration(milliseconds: 33))),
    );

    expect(output.point('leftShoulder')!.x, greaterThan(0.40));
    expect(output.point('leftShoulder')!.x, lessThan(0.44));
    expect(output.point('leftShoulder')!.likelihood, 0.95);
  });

  test('resets after a detector gap so movement is not dragged backward', () {
    final smoother = PoseLandmarkSmoother();
    final start = DateTime.utc(2026, 1, 1);

    smoother.smooth(_frame(0.40, start));
    final output = smoother.smooth(
      _frame(0.80, start.add(const Duration(milliseconds: 400))),
    );

    expect(output.point('leftShoulder')!.x, 0.80);
  });

  test(
    'dampens near-edge landmark jumps instead of treating them as speed',
    () {
      final smoother = PoseLandmarkSmoother();
      final start = DateTime.utc(2026, 1, 1);
      final first = NuvoPoseFrame(
        points: {
          'leftShoulder': NuvoPosePoint(
            x: 0.10,
            y: 0.4,
            z: 0,
            likelihood: 0.95,
          ),
          'rightShoulder': NuvoPosePoint(
            x: 0.90,
            y: 0.4,
            z: 0,
            likelihood: 0.95,
          ),
          'leftElbow': NuvoPosePoint(x: 0.20, y: 0.45, z: 0, likelihood: 0.95),
          'rightElbow': NuvoPosePoint(x: 0.80, y: 0.45, z: 0, likelihood: 0.95),
          'leftWrist': NuvoPosePoint(x: 0.25, y: 0.50, z: 0, likelihood: 0.95),
          'rightWrist': NuvoPosePoint(x: 0.75, y: 0.50, z: 0, likelihood: 0.95),
        },
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt: start,
      );
      smoother.smooth(first);

      final output = smoother.smooth(
        NuvoPoseFrame(
          points: {
            ...first.points,
            'leftShoulder': const NuvoPosePoint(
              x: 0.01,
              y: 0.4,
              z: 0,
              likelihood: 0.95,
            ),
            'rightShoulder': const NuvoPosePoint(
              x: 0.99,
              y: 0.4,
              z: 0,
              likelihood: 0.95,
            ),
          },
          imageWidth: 1000,
          imageHeight: 1000,
          createdAt: start.add(const Duration(milliseconds: 33)),
        ),
      );

      expect(output.point('leftShoulder')!.x, greaterThan(0.01));
      expect(output.point('leftShoulder')!.x, lessThan(0.10));
    },
  );
}
