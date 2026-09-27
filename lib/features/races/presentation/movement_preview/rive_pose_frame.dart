/// Runtime pose values consumed by the Nuvo stickman Rive rig.
///
/// Angles are degrees, matching the exported Rive bindings. Scale values are
/// values in the exported asset's normalized 0–100 input space. The asset's
/// Normalize converter maps 100 to the authored neutral length.
class RivePoseFrame {
  const RivePoseFrame({
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
    this.rootYOffset = 0,
  });

  /// Parses a remotely-fetched keyframe. Missing/invalid fields fall back to
  /// [neutral]'s value for that field — a partial or malformed remote
  /// keyframe degrades to a plausible pose rather than throwing, since this
  /// only ever drives a decorative preview.
  factory RivePoseFrame.fromJson(Map<String, dynamic> json) {
    double field(String key, double fallback) {
      final value = json[key];
      return value is num && value.isFinite ? value.toDouble() : fallback;
    }

    return RivePoseFrame(
      torsoAngle: field('torsoAngle', neutral.torsoAngle),
      leftShoulderAngle: field('leftShoulderAngle', neutral.leftShoulderAngle),
      leftElbowAngle: field('leftElbowAngle', neutral.leftElbowAngle),
      rightShoulderAngle: field(
        'rightShoulderAngle',
        neutral.rightShoulderAngle,
      ),
      rightElbowAngle: field('rightElbowAngle', neutral.rightElbowAngle),
      leftHipAngle: field('leftHipAngle', neutral.leftHipAngle),
      leftKneeAngle: field('leftKneeAngle', neutral.leftKneeAngle),
      rightHipAngle: field('rightHipAngle', neutral.rightHipAngle),
      rightKneeAngle: field('rightKneeAngle', neutral.rightKneeAngle),
      leftUpperArmScale: field('leftUpperArmScale', neutral.leftUpperArmScale),
      leftLowerArmScale: field('leftLowerArmScale', neutral.leftLowerArmScale),
      rightUpperArmScale: field(
        'rightUpperArmScale',
        neutral.rightUpperArmScale,
      ),
      rightLowerArmScale: field(
        'rightLowerArmScale',
        neutral.rightLowerArmScale,
      ),
      leftUpperLegScale: field('leftUpperLegScale', neutral.leftUpperLegScale),
      leftLowerLegScale: field('leftLowerLegScale', neutral.leftLowerLegScale),
      rightUpperLegScale: field(
        'rightUpperLegScale',
        neutral.rightUpperLegScale,
      ),
      rightLowerLegScale: field(
        'rightLowerLegScale',
        neutral.rightLowerLegScale,
      ),
      torsoScaleY: field('torsoScaleY', neutral.torsoScaleY),
      rootYOffset: field('rootYOffset', neutral.rootYOffset),
    );
  }

  Map<String, double> toJson() => {
    'torsoAngle': torsoAngle,
    'leftShoulderAngle': leftShoulderAngle,
    'leftElbowAngle': leftElbowAngle,
    'rightShoulderAngle': rightShoulderAngle,
    'rightElbowAngle': rightElbowAngle,
    'leftHipAngle': leftHipAngle,
    'leftKneeAngle': leftKneeAngle,
    'rightHipAngle': rightHipAngle,
    'rightKneeAngle': rightKneeAngle,
    'leftUpperArmScale': leftUpperArmScale,
    'leftLowerArmScale': leftLowerArmScale,
    'rightUpperArmScale': rightUpperArmScale,
    'rightLowerArmScale': rightLowerArmScale,
    'leftUpperLegScale': leftUpperLegScale,
    'leftLowerLegScale': leftLowerLegScale,
    'rightUpperLegScale': rightUpperLegScale,
    'rightLowerLegScale': rightLowerLegScale,
    'torsoScaleY': torsoScaleY,
    'rootYOffset': rootYOffset,
  };

  /// Neutral values read from the exported NuvoPoseModel instance.
  static const neutral = RivePoseFrame(
    // Empirically calibrated visible standing pose for the exported rig.
    torsoAngle: -90,
    leftShoulderAngle: -180,
    leftElbowAngle: 0,
    rightShoulderAngle: 180,
    // The exported default is 20, but the independently measured visible
    // straight-arm pose is 0 for the corrected binding.
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
  final double rootYOffset;

  RivePoseFrame copyWith({
    double? leftUpperArmScale,
    double? leftLowerArmScale,
    double? rightUpperArmScale,
    double? rightLowerArmScale,
    double? rootYOffset,
  }) => RivePoseFrame(
    torsoAngle: torsoAngle,
    leftShoulderAngle: leftShoulderAngle,
    leftElbowAngle: leftElbowAngle,
    rightShoulderAngle: rightShoulderAngle,
    rightElbowAngle: rightElbowAngle,
    leftHipAngle: leftHipAngle,
    leftKneeAngle: leftKneeAngle,
    rightHipAngle: rightHipAngle,
    rightKneeAngle: rightKneeAngle,
    leftUpperArmScale: leftUpperArmScale ?? this.leftUpperArmScale,
    leftLowerArmScale: leftLowerArmScale ?? this.leftLowerArmScale,
    rightUpperArmScale: rightUpperArmScale ?? this.rightUpperArmScale,
    rightLowerArmScale: rightLowerArmScale ?? this.rightLowerArmScale,
    leftUpperLegScale: leftUpperLegScale,
    leftLowerLegScale: leftLowerLegScale,
    rightUpperLegScale: rightUpperLegScale,
    rightLowerLegScale: rightLowerLegScale,
    torsoScaleY: torsoScaleY,
    rootYOffset: rootYOffset ?? this.rootYOffset,
  );

  RivePoseFrame lerp(RivePoseFrame other, double t) {
    final amount = t.isFinite ? t.clamp(0.0, 1.0) : 0.0;
    return RivePoseFrame(
      torsoAngle: _lerp(torsoAngle, other.torsoAngle, amount),
      leftShoulderAngle: _lerp(
        leftShoulderAngle,
        other.leftShoulderAngle,
        amount,
      ),
      leftElbowAngle: _lerp(leftElbowAngle, other.leftElbowAngle, amount),
      rightShoulderAngle: _lerp(
        rightShoulderAngle,
        other.rightShoulderAngle,
        amount,
      ),
      rightElbowAngle: _lerp(rightElbowAngle, other.rightElbowAngle, amount),
      leftHipAngle: _lerp(leftHipAngle, other.leftHipAngle, amount),
      leftKneeAngle: _lerp(leftKneeAngle, other.leftKneeAngle, amount),
      rightHipAngle: _lerp(rightHipAngle, other.rightHipAngle, amount),
      rightKneeAngle: _lerp(rightKneeAngle, other.rightKneeAngle, amount),
      leftUpperArmScale: _lerp(
        leftUpperArmScale,
        other.leftUpperArmScale,
        amount,
      ),
      leftLowerArmScale: _lerp(
        leftLowerArmScale,
        other.leftLowerArmScale,
        amount,
      ),
      rightUpperArmScale: _lerp(
        rightUpperArmScale,
        other.rightUpperArmScale,
        amount,
      ),
      rightLowerArmScale: _lerp(
        rightLowerArmScale,
        other.rightLowerArmScale,
        amount,
      ),
      leftUpperLegScale: _lerp(
        leftUpperLegScale,
        other.leftUpperLegScale,
        amount,
      ),
      leftLowerLegScale: _lerp(
        leftLowerLegScale,
        other.leftLowerLegScale,
        amount,
      ),
      rightUpperLegScale: _lerp(
        rightUpperLegScale,
        other.rightUpperLegScale,
        amount,
      ),
      rightLowerLegScale: _lerp(
        rightLowerLegScale,
        other.rightLowerLegScale,
        amount,
      ),
      torsoScaleY: _lerp(torsoScaleY, other.torsoScaleY, amount),
      rootYOffset: _lerp(rootYOffset, other.rootYOffset, amount),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  bool get isFiniteAndPositive =>
      mathsFinite(torsoAngle) &&
      mathsFinite(leftShoulderAngle) &&
      mathsFinite(leftElbowAngle) &&
      mathsFinite(rightShoulderAngle) &&
      mathsFinite(rightElbowAngle) &&
      mathsFinite(leftHipAngle) &&
      mathsFinite(leftKneeAngle) &&
      mathsFinite(rightHipAngle) &&
      mathsFinite(rightKneeAngle) &&
      mathsFinite(torsoScaleY) &&
      mathsFinite(rootYOffset) &&
      positiveFinite(leftUpperArmScale) &&
      positiveFinite(leftLowerArmScale) &&
      positiveFinite(rightUpperArmScale) &&
      positiveFinite(rightLowerArmScale) &&
      positiveFinite(leftUpperLegScale) &&
      positiveFinite(leftLowerLegScale) &&
      positiveFinite(rightUpperLegScale) &&
      positiveFinite(rightLowerLegScale);

  bool get hasFiniteAngles =>
      mathsFinite(torsoAngle) &&
      mathsFinite(leftShoulderAngle) &&
      mathsFinite(leftElbowAngle) &&
      mathsFinite(rightShoulderAngle) &&
      mathsFinite(rightElbowAngle) &&
      mathsFinite(leftHipAngle) &&
      mathsFinite(leftKneeAngle) &&
      mathsFinite(rightHipAngle) &&
      mathsFinite(rightKneeAngle);
}

bool mathsFinite(double value) => value.isFinite;

bool positiveFinite(double value) => value.isFinite && value > 0;
