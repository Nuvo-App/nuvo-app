// Regression tests for bugs found in the motion logic review.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

NuvoPosePoint p(double x, double y) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.95);
Map<String, NuvoPosePoint> stand({
  double lkx = 0.46,
  double lky = 0.75,
  double rkx = 0.54,
  double rky = 0.75,
}) => {
  'leftShoulder': p(0.42, 0.3),
  'rightShoulder': p(0.58, 0.3),
  'leftHip': p(0.45, 0.55),
  'rightHip': p(0.55, 0.55),
  'leftKnee': p(lkx, lky),
  'rightKnee': p(rkx, rky),
  'leftAnkle': p(0.46, 0.95),
  'rightAnkle': p(0.54, 0.95),
  'leftWrist': p(0.40, 0.55),
  'rightWrist': p(0.60, 0.55),
  'leftElbow': p(0.40, 0.42),
  'rightElbow': p(0.60, 0.42),
};
NuvoPoseFrame fr(Map<String, NuvoPosePoint> m, int ms) => NuvoPoseFrame(
  points: m,
  imageWidth: 640,
  imageHeight: 480,
  createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
);

void main() {
  test('plank counts a real horizontal plank', () {
    final v = createMotionValidator(AiMotionActivity.plankHold, 60)..start();
    var ms = 0;
    final m = {
      'leftShoulder': p(0.25, 0.5),
      'rightShoulder': p(0.26, 0.5),
      'leftHip': p(0.5, 0.52),
      'rightHip': p(0.51, 0.52),
      'leftKnee': p(0.65, 0.53),
      'rightKnee': p(0.66, 0.53),
      'leftAnkle': p(0.8, 0.55),
      'rightAnkle': p(0.81, 0.55),
    };
    for (var i = 0; i < 300; i++) {
      v.update(fr(m, ms));
      ms += 33;
    }
    expect(v.currentValue, greaterThanOrEqualTo(8));
  });
  test('plank does not count a person standing upright', () {
    final v = createMotionValidator(AiMotionActivity.plankHold, 60)..start();
    var ms = 0;
    for (var i = 0; i < 300; i++) {
      v.update(fr(stand(), ms));
      ms += 33;
    }
    expect(v.currentValue, 0);
  });
  for (final facingRight in [true, false]) {
    test(
      'marching counts steps from the side, facing either way (facingRight=$facingRight)',
      () {
        final v = createMotionValidator(AiMotionActivity.marchingInPlace, 1000)
          ..start();
        var ms = 0;
        // Side view: hips/shoulders nearly same x; knees separate in x when lifted.
        for (var rep = 0; rep < 10; rep++) {
          for (final leftUp in [true, false]) {
            for (var k = 0; k < 6; k++) {
              final dir = facingRight ? 1.0 : -1.0;
              final fwd = 0.12 * dir;
              final m = stand(
                lkx: 0.5 + (leftUp ? fwd : 0),
                lky: leftUp ? 0.62 : 0.78,
                rkx: 0.5 + (leftUp ? 0 : fwd),
                rky: leftUp ? 0.78 : 0.62,
              );
              // side view: shoulders/hips collapse
              m['leftShoulder'] = p(0.5, 0.3);
              m['rightShoulder'] = p(0.51, 0.3);
              m['leftHip'] = p(0.5, 0.55);
              m['rightHip'] = p(0.51, 0.55);
              v.update(fr(m, ms));
              ms += 33;
            }
          }
        }
        expect(v.currentValue, inInclusiveRange(14, 20));
      },
    );
  }
  test('marching front view', () {
    final v = createMotionValidator(AiMotionActivity.marchingInPlace, 1000)
      ..start();
    var ms = 0;
    for (var rep = 0; rep < 10; rep++) {
      for (final leftUp in [true, false]) {
        for (var k = 0; k < 6; k++) {
          v.update(
            fr(stand(lky: leftUp ? 0.62 : 0.78, rky: leftUp ? 0.78 : 0.62), ms),
          );
          ms += 33;
        }
      }
    }
    expect(v.currentValue, inInclusiveRange(14, 20));
  });
}
