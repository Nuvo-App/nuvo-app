import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/widgets/movement_demo.dart';
import 'package:nuvo/features/races/presentation/widgets/multiphase_movement_demos.dart';
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
    'burpees': burpeesDemo,
    'mountainClimbers': mountainClimbersDemo,
    'basketballShot': basketballShotDemo,
  };

  for (final entry in demos.entries) {
    group(entry.key, () {
      final demo = entry.value;

      test('has at least 4 poses', () {
        expect(demo.poses.length, greaterThanOrEqualTo(4));
      });

      test('loops: first pose equals last pose', () {
        expect(_joints(demo.poses.first), _joints(demo.poses.last));
      });

      test('duration is between 800ms and 6000ms', () {
        expect(demo.duration.inMilliseconds, greaterThanOrEqualTo(800));
        expect(demo.duration.inMilliseconds, lessThanOrEqualTo(6000));
      });

      test('some joint moves more than 0.05 between frames', () {
        var maxMove = 0.0;
        for (var i = 0; i < demo.poses.length - 1; i++) {
          final a = _joints(demo.poses[i]);
          final b = _joints(demo.poses[i + 1]);
          for (var j = 0; j < a.length; j++) {
            final d = (a[j] - b[j]).distance;
            if (d > maxMove) maxMove = d;
          }
        }
        expect(maxMove, greaterThan(0.05));
      });
    });
  }
}
