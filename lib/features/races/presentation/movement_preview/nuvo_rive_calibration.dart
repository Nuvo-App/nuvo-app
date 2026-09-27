import 'dart:convert';

import 'package:rive/rive.dart';

/// The raw numeric controls exported by NuvoPoseModel.
class NuvoRiveCalibrationContract {
  const NuvoRiveCalibrationContract._();

  static const angleProperties = <String>[
    'leftShoulderAngle',
    'leftElbowAngle',
    'rightShoulderAngle',
    'rightElbowAngle',
    'leftHipAngle',
    'leftKneeAngle',
    'rightHipAngle',
    'rightKneeAngle',
    'torsoAngle',
  ];

  static const scaleProperties = <String>[
    'leftUpperArmScale',
    'leftLowerArmScale',
    'rightUpperArmScale',
    'rightLowerArmScale',
    'leftUpperLegScale',
    'leftLowerLegScale',
    'rightUpperLegScale',
    'rightLowerLegScale',
    'torsoScaleY',
  ];

  static const allProperties = <String>[...angleProperties, ...scaleProperties];

  static bool isScale(String property) => scaleProperties.contains(property);

  static double minimum(String property) => isScale(property) ? 0 : -360;

  static double maximum(String property) => isScale(property) ? 200 : 360;
}

/// A complete raw pose copied from one NuvoPoseModel instance.
class NuvoRiveCalibrationPose {
  NuvoRiveCalibrationPose(Map<String, double> values)
    : values = Map.unmodifiable(values);

  factory NuvoRiveCalibrationPose.read(ViewModelInstance instance) {
    final values = <String, double>{};
    for (final name in NuvoRiveCalibrationContract.allProperties) {
      final property = instance.number(name);
      if (property == null) {
        throw StateError('NuvoPoseModel is missing $name');
      }
      values[name] = property.value;
    }
    return NuvoRiveCalibrationPose(values);
  }

  final Map<String, double> values;

  void applyTo(ViewModelInstance instance) {
    for (final entry in values.entries) {
      instance.number(entry.key)?.value = entry.value;
    }
    instance.requestAdvance();
  }

  String toJsonLikeString({String? label}) {
    final encoded = const JsonEncoder.withIndent('  ').convert(values);
    if (label == null || label.isEmpty) return encoded;
    return '$label: $encoded';
  }
}

/// Temporary in-memory ground-truth storage for the developer calibration
/// workflow. The values are intentionally not used by the animation yet.
class NuvoJumpingJackCalibrationStore {
  static NuvoRiveCalibrationPose? closed;
  static NuvoRiveCalibrationPose? open;
}
