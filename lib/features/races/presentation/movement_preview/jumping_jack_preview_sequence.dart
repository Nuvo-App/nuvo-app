import 'dart:math' as math;

import 'jumping_jack_human_motion_profile.dart';
import 'rive_pose_frame.dart';

/// Drives the locked Rive endpoints with a normalized human motion profile.
class JumpingJackPreviewSequence {
  const JumpingJackPreviewSequence({required this.closed, required this.open});

  static const duration = JumpingJackHumanMotionProfile.cycleDuration;

  final RivePoseFrame closed;
  final RivePoseFrame open;

  RivePoseFrame poseAt(double normalizedTime) {
    final t = normalizedTime.isFinite
        ? normalizedTime - normalizedTime.floorToDouble()
        : 0.0;
    final shoulders = JumpingJackHumanMotionProfile.sample(
      JumpingJackHumanMotionProfile.armRaise,
      t,
    );
    final elbows = JumpingJackHumanMotionProfile.sample(
      JumpingJackHumanMotionProfile.elbowBend,
      t,
    );
    final hips = JumpingJackHumanMotionProfile.sample(
      JumpingJackHumanMotionProfile.legSpread,
      t,
    );
    // The body lands in both semantic poses. Use one independent arc while
    // opening and another while closing, rather than carrying one root arc
    // across the full cycle. This keeps the open pose grounded at phase 0.5
    // and the closed pose grounded at the loop seam.
    final localTime = t < 0.5 ? t * 2 : (t - 0.5) * 2;
    final root = open.rootYOffset * math.sin(math.pi * localTime);

    return _lerpMovingControls(
      closed,
      open,
      hips: hips,
      shoulders: shoulders,
      elbows: elbows,
      rootYOffset: root,
    );
  }

  static RivePoseFrame _lerpMovingControls(
    RivePoseFrame from,
    RivePoseFrame to, {
    required double hips,
    required double shoulders,
    required double elbows,
    required double rootYOffset,
  }) => RivePoseFrame(
    torsoAngle: from.torsoAngle,
    leftShoulderAngle: _lerpAngle(
      from.leftShoulderAngle,
      to.leftShoulderAngle,
      shoulders,
    ),
    leftElbowAngle: _lerpAngle(from.leftElbowAngle, to.leftElbowAngle, elbows),
    rightShoulderAngle: _lerpAngle(
      from.rightShoulderAngle,
      to.rightShoulderAngle,
      shoulders,
    ),
    rightElbowAngle: _lerpAngle(
      from.rightElbowAngle,
      to.rightElbowAngle,
      elbows,
    ),
    leftHipAngle: _lerpAngle(from.leftHipAngle, to.leftHipAngle, hips),
    leftKneeAngle: from.leftKneeAngle,
    rightHipAngle: _lerpAngle(from.rightHipAngle, to.rightHipAngle, hips),
    rightKneeAngle: from.rightKneeAngle,
    leftUpperArmScale: from.leftUpperArmScale,
    leftLowerArmScale: from.leftLowerArmScale,
    rightUpperArmScale: from.rightUpperArmScale,
    rightLowerArmScale: from.rightLowerArmScale,
    leftUpperLegScale: from.leftUpperLegScale,
    leftLowerLegScale: from.leftLowerLegScale,
    rightUpperLegScale: from.rightUpperLegScale,
    rightLowerLegScale: from.rightLowerLegScale,
    torsoScaleY: from.torsoScaleY,
    rootYOffset: rootYOffset,
  );

  static double _lerpAngle(double from, double to, double amount) {
    var delta = to - from;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return from + delta * amount;
  }
}
