import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/movement_preview/nuvo_rig_resolver.dart';
import 'package:nuvo/features/races/presentation/movement_preview/nuvo_semantic_pose.dart';

void main() {
  const resolver = NuvoRigResolver();

  test('semantic neutral resolves to calibrated standing values', () {
    final frame = resolver.resolve(NuvoHumanPose.jumpingJackClosed);
    expect(frame.leftShoulderAngle, closeTo(-180, 0.1));
    expect(frame.rightShoulderAngle, closeTo(180, 0.1));
    expect(frame.leftElbowAngle, 0);
    expect(frame.rightElbowAngle, 0);
    expect(frame.leftUpperArmScale, 100);
    expect(frame.rightUpperLegScale, 100);
  });

  test('semantic elbow bend maps independently on both sides', () {
    final frame = resolver.resolve(NuvoHumanPose.jumpingJackOpen);
    expect(frame.leftElbowAngle, closeTo(68.5, 0.2));
    expect(frame.rightElbowAngle, closeTo(34.25, 0.2));
    expect(frame.leftShoulderAngle, closeTo(-35, 1));
    expect(frame.rightShoulderAngle, closeTo(35, 1));
    expect(frame.leftHipAngle, closeTo(-130.75, 0.2));
    expect(frame.rightHipAngle, closeTo(130.75, 0.2));
  });

  test('semantic interpolation has exact endpoints and midpoint', () {
    final closed = NuvoHumanPose.jumpingJackClosed;
    final open = NuvoHumanPose.jumpingJackOpen;
    expect(closed.lerp(open, 0).leftArm.lowerDirection.y, closeTo(0.99, 0.01));
    expect(closed.lerp(open, 1).leftArm.lowerDirection.x, closeTo(0.4, 0.01));
    expect(closed.lerp(open, 0.5).leftArm.lowerDirection.x, lessThan(0.2));
  });

  test('open geometry puts elbows outside and hands above them', () {
    const open = NuvoHumanPose.jumpingJackOpen;
    expect(open.leftArm.upperDirection.x, lessThan(0));
    expect(open.rightArm.upperDirection.x, greaterThan(0));
    expect(open.leftArm.lowerDirection.x, greaterThan(0));
    expect(open.rightArm.lowerDirection.x, lessThan(0));
    expect(open.leftArm.lowerDirection.y, lessThan(0));
    expect(open.rightArm.lowerDirection.y, lessThan(0));
  });
}
