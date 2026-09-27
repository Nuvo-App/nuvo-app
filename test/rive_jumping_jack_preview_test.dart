import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/movement_preview/jumping_jack_preview_sequence.dart';
import 'package:nuvo/features/races/presentation/movement_preview/rive_pose_frame.dart';

void main() {
  const sequence = JumpingJackPreviewSequence(
    closed: RivePoseFrame(
      torsoAngle: 0,
      leftShoulderAngle: -10,
      leftElbowAngle: 0,
      rightShoulderAngle: 10,
      rightElbowAngle: 0,
      leftHipAngle: -10,
      leftKneeAngle: 0,
      rightHipAngle: 10,
      rightKneeAngle: 0,
      leftUpperArmScale: 1,
      leftLowerArmScale: 1,
      rightUpperArmScale: 1,
      rightLowerArmScale: 1,
      leftUpperLegScale: 1,
      leftLowerLegScale: 1,
      rightUpperLegScale: 1,
      rightLowerLegScale: 1,
      torsoScaleY: 1,
    ),
    open: RivePoseFrame(
      torsoAngle: 0,
      leftShoulderAngle: 10,
      leftElbowAngle: 8,
      rightShoulderAngle: -10,
      rightElbowAngle: 12,
      leftHipAngle: -30,
      leftKneeAngle: 0,
      rightHipAngle: 30,
      rightKneeAngle: 0,
      leftUpperArmScale: 1,
      leftLowerArmScale: 1,
      rightUpperArmScale: 1,
      rightLowerArmScale: 1,
      leftUpperLegScale: 1,
      leftLowerLegScale: 1,
      rightUpperLegScale: 1,
      rightLowerLegScale: 1,
      torsoScaleY: 1,
      rootYOffset: -14,
    ),
  );

  test('loops back to the closed pose', () {
    final start = sequence.poseAt(0);
    final end = sequence.poseAt(1);
    expect(end.leftShoulderAngle, closeTo(start.leftShoulderAngle, 0.001));
    expect(end.rightHipAngle, closeTo(start.rightHipAngle, 0.001));
  });

  test('open phase raises arms and spreads legs', () {
    final closed = sequence.poseAt(0);
    final open = sequence.poseAt(0.5);
    expect(open.leftShoulderAngle, isNot(closed.leftShoulderAngle));
    expect(open.rightShoulderAngle, isNot(closed.rightShoulderAngle));
    expect(open.leftHipAngle, isNot(closed.leftHipAngle));
    expect(open.rightHipAngle, isNot(closed.rightHipAngle));
  });

  test('elbows are straight when closed and softly bent when open', () {
    final closed = sequence.poseAt(0);
    final open = sequence.poseAt(0.5);
    expect(closed.leftElbowAngle, closeTo(0, 0.001));
    expect(closed.rightElbowAngle, closeTo(0, 0.001));
    expect(open.leftElbowAngle, greaterThan(closed.leftElbowAngle));
    expect(open.rightElbowAngle, greaterThan(closed.rightElbowAngle));
  });

  test('invalid time remains finite', () {
    for (final value in [double.nan, double.infinity, -double.infinity, -2.5]) {
      final pose = sequence.poseAt(value);
      expect(pose.hasFiniteAngles, isTrue);
      expect(pose.leftShoulderAngle.isFinite, isTrue);
    }
    final midpoint = RivePoseFrame.neutral.lerp(
      RivePoseFrame.neutral,
      double.nan,
    );
    expect(midpoint.isFiniteAndPositive, isTrue);
  });

  test('root lands at closed and open phases with two separate jump arcs', () {
    expect(sequence.poseAt(0).rootYOffset, closeTo(0, 0.001));
    expect(sequence.poseAt(0.25).rootYOffset, lessThan(0));
    expect(sequence.poseAt(0.5).rootYOffset, closeTo(0, 0.001));
    expect(sequence.poseAt(0.75).rootYOffset, lessThan(0));
    expect(sequence.poseAt(1).rootYOffset, closeTo(0, 0.001));
  });
}
