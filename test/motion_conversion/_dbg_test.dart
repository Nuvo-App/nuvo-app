import 'package:flutter_test/flutter_test.dart';
import 'conversion_pose_kit.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';

void main() {
  test('dump armRaisesDemo keyframes', () {
    final keys = demoPoseMapsFor(AiMotionActivity.armRaises)!;
    for (var k = 0; k < keys.length; k++) {
      final p = keys[k];
      final shoulderY = (p['leftShoulder']!.dy + p['rightShoulder']!.dy) / 2;
      final hipY = (p['leftHip']!.dy + p['rightHip']!.dy) / 2;
      final torso = (hipY - shoulderY).abs().clamp(0.12, 0.6);
      final upGate = shoulderY - torso * 0.16;
      print('key$k wristY=${p['leftWrist']!.dy.toStringAsFixed(3)} '
          'shoulderY=${shoulderY.toStringAsFixed(3)} upGate=${upGate.toStringAsFixed(3)} '
          'up=${p['leftWrist']!.dy < upGate && p['rightWrist']!.dy < upGate}');
    }
    final v = createMotionValidator(AiMotionActivity.armRaises, 999);
    v.start();
    final poses = interpolatePoses(keys, framesPerSegment: 6);
    final frames = framesFromPoses(poses);
    for (var i = 0; i < frames.length; i++) { v.update(frames[i]); }
    print('NATIVE demo count=${v.currentValue}');
  });
}
