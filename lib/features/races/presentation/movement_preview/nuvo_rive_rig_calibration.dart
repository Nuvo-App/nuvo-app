import 'package:rive/rive.dart';

import 'rive_pose_frame.dart';

/// Runtime calibration for the exported `nuvo_stickman.riv` rig.
///
/// The raw View Model defaults are retained for diagnostics. The asset's
/// Normalize bindings require a scale input of 100 for the authored neutral
/// limb length; a raw scale input of 0 produces no visible limb.
class NuvoRiveRigCalibration {
  const NuvoRiveRigCalibration({
    required this.torsoAngle,
    required this.leftShoulderAngle,
    required this.leftElbowAngle,
    required this.rightShoulderAngle,
    required this.rightElbowAngle,
    required this.leftHipAngle,
    required this.leftKneeAngle,
    required this.rightHipAngle,
    required this.rightKneeAngle,
    required this.leftUpperArmScale,
    required this.leftLowerArmScale,
    required this.rightUpperArmScale,
    required this.rightLowerArmScale,
    required this.leftUpperLegScale,
    required this.leftLowerLegScale,
    required this.rightUpperLegScale,
    required this.rightLowerLegScale,
    required this.torsoScaleY,
  });

  /// Values read from the default NuvoPoseModel instance before writing.
  static const exportedDefaults = NuvoRiveRigCalibration(
    torsoAngle: 0,
    leftShoulderAngle: -90,
    leftElbowAngle: 0,
    rightShoulderAngle: 0,
    rightElbowAngle: 20,
    leftHipAngle: 0,
    leftKneeAngle: 0,
    rightHipAngle: 0,
    rightKneeAngle: 0,
    leftUpperArmScale: 0,
    leftLowerArmScale: 0,
    rightUpperArmScale: 0,
    rightLowerArmScale: 0,
    leftUpperLegScale: 0,
    leftLowerLegScale: 0,
    rightUpperLegScale: 0,
    rightLowerLegScale: 0,
    torsoScaleY: 0,
  );

  factory NuvoRiveRigCalibration.fromViewModelInstance(
    ViewModelInstance instance,
  ) => NuvoRiveRigCalibration(
    torsoAngle: _read(instance, 'torsoAngle'),
    leftShoulderAngle: _read(instance, 'leftShoulderAngle'),
    leftElbowAngle: _read(instance, 'leftElbowAngle'),
    rightShoulderAngle: _read(instance, 'rightShoulderAngle'),
    rightElbowAngle: _read(instance, 'rightElbowAngle'),
    leftHipAngle: _read(instance, 'leftHipAngle'),
    leftKneeAngle: _read(instance, 'leftKneeAngle'),
    rightHipAngle: _read(instance, 'rightHipAngle'),
    rightKneeAngle: _read(instance, 'rightKneeAngle'),
    leftUpperArmScale: _read(instance, 'leftUpperArmScale'),
    leftLowerArmScale: _read(instance, 'leftLowerArmScale'),
    rightUpperArmScale: _read(instance, 'rightUpperArmScale'),
    rightLowerArmScale: _read(instance, 'rightLowerArmScale'),
    leftUpperLegScale: _read(instance, 'leftUpperLegScale'),
    leftLowerLegScale: _read(instance, 'leftLowerLegScale'),
    rightUpperLegScale: _read(instance, 'rightUpperLegScale'),
    rightLowerLegScale: _read(instance, 'rightLowerLegScale'),
    torsoScaleY: _read(instance, 'torsoScaleY'),
  );

  /// Empirically calibrated visible standing pose for this exported rig.
  static const standing = NuvoRiveRigCalibration(
    torsoAngle: -90,
    leftShoulderAngle: -180,
    leftElbowAngle: 0,
    rightShoulderAngle: 180,
    // The raw default is 20, but the independently measured visible
    // straight-arm base is 0 for the corrected binding.
    rightElbowAngle: 0,
    leftHipAngle: -180,
    leftKneeAngle: 0,
    rightHipAngle: 180,
    rightKneeAngle: 0,
    leftUpperArmScale: 100,
    leftLowerArmScale: 100,
    rightUpperArmScale: 100,
    rightLowerArmScale: 100,
    leftUpperLegScale: 100,
    leftLowerLegScale: 100,
    rightUpperLegScale: 100,
    rightLowerLegScale: 100,
    torsoScaleY: 100,
  );

  final double torsoAngle;
  final double leftShoulderAngle;
  final double leftElbowAngle;
  final double rightShoulderAngle;
  final double rightElbowAngle;
  final double leftHipAngle;
  final double leftKneeAngle;
  final double rightHipAngle;
  final double rightKneeAngle;
  final double leftUpperArmScale;
  final double leftLowerArmScale;
  final double rightUpperArmScale;
  final double rightLowerArmScale;
  final double leftUpperLegScale;
  final double leftLowerLegScale;
  final double rightUpperLegScale;
  final double rightLowerLegScale;
  final double torsoScaleY;

  RivePoseFrame resolve(RigPoseOffset offset) => RivePoseFrame(
    torsoAngle: torsoAngle + offset.torsoAngle,
    leftShoulderAngle: leftShoulderAngle + offset.leftShoulderAngle,
    leftElbowAngle: leftElbowAngle + offset.leftElbowAngle,
    rightShoulderAngle: rightShoulderAngle + offset.rightShoulderAngle,
    rightElbowAngle: rightElbowAngle + offset.rightElbowAngle,
    leftHipAngle: leftHipAngle + offset.leftHipAngle,
    leftKneeAngle: leftKneeAngle + offset.leftKneeAngle,
    rightHipAngle: rightHipAngle + offset.rightHipAngle,
    rightKneeAngle: rightKneeAngle + offset.rightKneeAngle,
    leftUpperArmScale: leftUpperArmScale,
    leftLowerArmScale: leftLowerArmScale,
    rightUpperArmScale: rightUpperArmScale,
    rightLowerArmScale: rightLowerArmScale,
    leftUpperLegScale: leftUpperLegScale,
    leftLowerLegScale: leftLowerLegScale,
    rightUpperLegScale: rightUpperLegScale,
    rightLowerLegScale: rightLowerLegScale,
    torsoScaleY: torsoScaleY,
  );
}

class RigPoseOffset {
  const RigPoseOffset({
    this.torsoAngle = 0,
    this.leftShoulderAngle = 0,
    this.leftElbowAngle = 0,
    this.rightShoulderAngle = 0,
    this.rightElbowAngle = 0,
    this.leftHipAngle = 0,
    this.leftKneeAngle = 0,
    this.rightHipAngle = 0,
    this.rightKneeAngle = 0,
  });

  static const zero = RigPoseOffset();

  final double torsoAngle;
  final double leftShoulderAngle;
  final double leftElbowAngle;
  final double rightShoulderAngle;
  final double rightElbowAngle;
  final double leftHipAngle;
  final double leftKneeAngle;
  final double rightHipAngle;
  final double rightKneeAngle;
}

double _read(ViewModelInstance instance, String name) {
  final property = instance.number(name);
  if (property == null) {
    throw StateError('NuvoPoseModel is missing $name');
  }
  return property.value;
}
