import 'dart:math' as math;

import 'nuvo_rive_rig_calibration.dart';
import 'nuvo_semantic_pose.dart';
import 'rive_pose_frame.dart';

/// Converts global two-link geometry into calibrated Rive values.
///
/// Movement code supplies shoulder→elbow and elbow→wrist directions. This
/// resolver accounts for authored rest orientations, side signs, and local
/// child-joint rotation.
class NuvoRigResolver {
  const NuvoRigResolver({this.calibration = NuvoRiveRigCalibration.standing});

  final NuvoRiveRigCalibration calibration;

  RivePoseFrame resolve(NuvoHumanPose pose) {
    final leftArm = _resolveArm(pose.leftArm, isLeft: true);
    final rightArm = _resolveArm(pose.rightArm, isLeft: false);
    final leftLeg = _resolveLeg(pose.leftLeg, isLeft: true);
    final rightLeg = _resolveLeg(pose.rightLeg, isLeft: false);
    return RivePoseFrame(
      torsoAngle: calibration.torsoAngle + pose.torsoLean,
      leftShoulderAngle: leftArm.shoulder,
      leftElbowAngle: leftArm.elbow,
      rightShoulderAngle: rightArm.shoulder,
      rightElbowAngle: rightArm.elbow,
      leftHipAngle: leftLeg.hip,
      leftKneeAngle: leftLeg.knee,
      rightHipAngle: rightLeg.hip,
      rightKneeAngle: rightLeg.knee,
      leftUpperArmScale: 100 * pose.leftArm.foreshortening,
      leftLowerArmScale: 100 * pose.leftArm.foreshortening,
      rightUpperArmScale: 100 * pose.rightArm.foreshortening,
      rightLowerArmScale: 100 * pose.rightArm.foreshortening,
      leftUpperLegScale: 100 * pose.leftLeg.foreshortening,
      leftLowerLegScale: 100 * pose.leftLeg.foreshortening,
      rightUpperLegScale: 100 * pose.rightLeg.foreshortening,
      rightLowerLegScale: 100 * pose.rightLeg.foreshortening,
      torsoScaleY: 100,
      rootYOffset: pose.rootYOffset,
    );
  }

  _ResolvedArm _resolveArm(NuvoArmPose pose, {required bool isLeft}) {
    final upperAngle = _degrees(pose.upperDirection.globalAngleRadians);
    final lowerAngle = _degrees(pose.lowerDirection.globalAngleRadians);
    final localBend = _shortestDelta(upperAngle, lowerAngle);
    final shoulderBaseVisual = isLeft ? 98.5 : 81.5;
    final shoulderRawPerDegree = isLeft ? -0.622 : 1.146;
    final shoulderBase = isLeft
        ? calibration.leftShoulderAngle
        : calibration.rightShoulderAngle;
    final elbowBase = isLeft
        ? calibration.leftElbowAngle
        : calibration.rightElbowAngle;
    // Independent corrected-rig elbow calibration. The right binding uses an
    // opposite authored sign and half the raw response of the left binding.
    final elbowRawPerDegree = isLeft ? 1.0 : -0.5;
    return _ResolvedArm(
      shoulder:
          shoulderBase +
          (upperAngle - shoulderBaseVisual) * shoulderRawPerDegree,
      elbow: elbowBase + localBend * elbowRawPerDegree,
    );
  }

  _ResolvedLeg _resolveLeg(NuvoLegPose pose, {required bool isLeft}) {
    final upperAngle = _degrees(pose.upperDirection.globalAngleRadians);
    final lowerAngle = _degrees(pose.lowerDirection.globalAngleRadians);
    final localBend = _shortestDelta(upperAngle, lowerAngle);
    final hipBaseVisual = isLeft ? 94.5 : 85.5;
    final hipRawPerDegree = 1.216;
    final hipBase = isLeft
        ? calibration.leftHipAngle
        : calibration.rightHipAngle;
    final kneeBase = isLeft
        ? calibration.leftKneeAngle
        : calibration.rightKneeAngle;
    return _ResolvedLeg(
      hip: hipBase + (upperAngle - hipBaseVisual) * hipRawPerDegree,
      knee: kneeBase + localBend,
    );
  }

  static double _degrees(double radians) => radians * 180 / math.pi;

  static double _shortestDelta(double from, double to) {
    var delta = to - from;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return delta;
  }
}

class _ResolvedArm {
  const _ResolvedArm({required this.shoulder, required this.elbow});
  final double shoulder;
  final double elbow;
}

class _ResolvedLeg {
  const _ResolvedLeg({required this.hip, required this.knee});
  final double hip;
  final double knee;
}
