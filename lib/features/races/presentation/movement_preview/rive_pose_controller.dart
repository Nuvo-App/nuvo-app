import 'package:rive/rive.dart';

import 'rive_pose_frame.dart';

/// Applies typed Nuvo poses to an exported Rive View Model.
class RivePoseController {
  RivePoseController(ViewModelInstance instance) : _instance = instance {
    for (final name in _propertyNames) {
      final property = _read(instance, name);
      if (property == null) {
        missingProperties.add(name);
      }
    }
  }

  static const _propertyNames = [
    'leftShoulderAngle',
    'leftElbowAngle',
    'rightShoulderAngle',
    'rightElbowAngle',
    'leftHipAngle',
    'leftKneeAngle',
    'rightHipAngle',
    'rightKneeAngle',
  ];

  final ViewModelInstance _instance;
  final missingProperties = <String>[];

  late final ViewModelInstanceNumber? _leftShoulderAngle = _read(
    _instance,
    'leftShoulderAngle',
  );
  late final ViewModelInstanceNumber? _leftElbowAngle = _read(
    _instance,
    'leftElbowAngle',
  );
  late final ViewModelInstanceNumber? _rightShoulderAngle = _read(
    _instance,
    'rightShoulderAngle',
  );
  late final ViewModelInstanceNumber? _rightElbowAngle = _read(
    _instance,
    'rightElbowAngle',
  );
  late final ViewModelInstanceNumber? _leftHipAngle = _read(
    _instance,
    'leftHipAngle',
  );
  late final ViewModelInstanceNumber? _leftKneeAngle = _read(
    _instance,
    'leftKneeAngle',
  );
  late final ViewModelInstanceNumber? _rightHipAngle = _read(
    _instance,
    'rightHipAngle',
  );
  late final ViewModelInstanceNumber? _rightKneeAngle = _read(
    _instance,
    'rightKneeAngle',
  );

  bool get isUsable => missingProperties.isEmpty;

  /// Writes the complete calibrated frame once, immediately after binding.
  /// The exported scale bindings have zero defaults, so the View Model must
  /// receive the neutral frame before the first bound frame is painted.
  void apply(RivePoseFrame frame) {
    if (!frame.isFiniteAndPositive) return;
    _leftShoulderAngle?.value = frame.leftShoulderAngle;
    _leftElbowAngle?.value = frame.leftElbowAngle;
    _rightShoulderAngle?.value = frame.rightShoulderAngle;
    _rightElbowAngle?.value = frame.rightElbowAngle;
    _leftHipAngle?.value = frame.leftHipAngle;
    _rightHipAngle?.value = frame.rightHipAngle;
    _instance.number('torsoAngle')?.value = frame.torsoAngle;
    _instance.number('leftKneeAngle')?.value = frame.leftKneeAngle;
    _instance.number('rightKneeAngle')?.value = frame.rightKneeAngle;
    _instance.number('leftUpperArmScale')?.value = frame.leftUpperArmScale;
    _instance.number('leftLowerArmScale')?.value = frame.leftLowerArmScale;
    _instance.number('rightUpperArmScale')?.value = frame.rightUpperArmScale;
    _instance.number('rightLowerArmScale')?.value = frame.rightLowerArmScale;
    _instance.number('leftUpperLegScale')?.value = frame.leftUpperLegScale;
    _instance.number('leftLowerLegScale')?.value = frame.leftLowerLegScale;
    _instance.number('rightUpperLegScale')?.value = frame.rightUpperLegScale;
    _instance.number('rightLowerLegScale')?.value = frame.rightLowerLegScale;
    _instance.number('torsoScaleY')?.value = frame.torsoScaleY;
    _instance.requestAdvance();
  }

  /// Applies the articulated joint angles used by non-jumping-jack previews.
  /// Scale inputs remain at their initialized neutral values so movement
  /// previews do not distort authored limb lengths.
  void applyMotion(RivePoseFrame frame) {
    if (!frame.hasFiniteAngles) return;
    _leftShoulderAngle?.value = frame.leftShoulderAngle;
    _leftElbowAngle?.value = frame.leftElbowAngle;
    _rightShoulderAngle?.value = frame.rightShoulderAngle;
    _rightElbowAngle?.value = frame.rightElbowAngle;
    _leftHipAngle?.value = frame.leftHipAngle;
    _leftKneeAngle?.value = frame.leftKneeAngle;
    _rightHipAngle?.value = frame.rightHipAngle;
    _rightKneeAngle?.value = frame.rightKneeAngle;
    _instance.requestAdvance();
  }

  /// Updates only the six jumping-jack controls during animation.
  /// Elbows, knees, scales, and torso scale remain at their calibrated values.
  void applyJumpingJackMotion(RivePoseFrame frame) {
    if (!frame.hasFiniteAngles) return;
    _leftShoulderAngle?.value = frame.leftShoulderAngle;
    _rightShoulderAngle?.value = frame.rightShoulderAngle;
    _leftElbowAngle?.value = frame.leftElbowAngle;
    _rightElbowAngle?.value = frame.rightElbowAngle;
    _leftHipAngle?.value = frame.leftHipAngle;
    _rightHipAngle?.value = frame.rightHipAngle;
    _instance.requestAdvance();
  }

  ViewModelInstanceNumber? _read(ViewModelInstance instance, String name) =>
      instance.number(name);
}
