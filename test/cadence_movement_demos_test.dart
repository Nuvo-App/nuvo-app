import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/widgets/cadence_movement_demos.dart';
import 'package:nuvo/features/races/presentation/widgets/movement_demo.dart';
import 'package:nuvo/features/races/presentation/widgets/nuvo_character_painter.dart';

List<Offset> _joints(NuvoCharacterPose p) => [
      p.head,
      p.neck,
      p.leftShoulder,
      p.rightShoulder,
      p.leftElbow,
      p.rightElbow,
      p.leftWrist,
      p.rightWrist,
      p.leftHip,
      p.rightHip,
      p.leftKnee,
      p.rightKnee,
      p.leftAnkle,
      p.rightAnkle,
    ];

void main() {
  final demos = <String, MovementDemo>{
    'runningInPlace': runningInPlaceDemo,
    'walkingInPlace': walkingInPlaceDemo,
    'marchingInPlace': marchingInPlaceDemo,
    'treadmillRunning': treadmillRunningDemo,
    'buttKicks': buttKicksDemo,
    'calfRaises': calfRaisesDemo,
    'stepUps': stepUpsDemo,
    'lateralSteps': lateralStepsDemo,
  };

  for (final entry in demos.entries) {
    group(entry.key, () {
      final demo = entry.value;

      test('has at least 3 poses and a sane duration', () {
        expect(demo.poses.length, greaterThanOrEqualTo(3));
        expect(demo.duration.inMilliseconds, inInclusiveRange(800, 6000));
      });

      test('first and last pose match so the loop is seamless', () {
        final a = _joints(demo.poses.first);
        final b = _joints(demo.poses.last);
        for (var i = 0; i < a.length; i++) {
          expect(a[i], b[i], reason: 'joint $i differs');
        }
      });

      test('frames actually differ', () {
        final first = _joints(demo.poses.first);
        var maxMove = 0.0;
        for (final pose in demo.poses) {
          final j = _joints(pose);
          for (var i = 0; i < j.length; i++) {
            final d = (j[i] - first[i]).distance;
            if (d > maxMove) maxMove = d;
          }
        }
        expect(maxMove, greaterThan(0.05));
      });

      test('all joints stay inside the normalized frame', () {
        for (final pose in demo.poses) {
          for (final o in _joints(pose)) {
            expect(o.dx, inInclusiveRange(0.0, 1.0));
            expect(o.dy, inInclusiveRange(0.0, 1.0));
          }
        }
      });
    });
  }
}
