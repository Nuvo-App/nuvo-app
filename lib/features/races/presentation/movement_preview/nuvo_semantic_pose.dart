import 'dart:math' as math;

/// Screen-space direction used by movement definitions.
///
/// +x points right and +y points down. These are global segment directions,
/// not Rive-local rotations.
class NuvoDirection2D {
  const NuvoDirection2D(this.x, this.y);

  final double x;
  final double y;

  double get globalAngleRadians => math.atan2(y, x);

  NuvoDirection2D mirrored() => NuvoDirection2D(-x, y);
}

class NuvoArmPose {
  const NuvoArmPose({
    required this.upperDirection,
    required this.lowerDirection,
    this.foreshortening = 1,
  });

  /// Direction from shoulder to elbow in global screen space.
  final NuvoDirection2D upperDirection;

  /// Direction from elbow to wrist in global screen space.
  final NuvoDirection2D lowerDirection;

  /// Segment length multiplier. 1 is the calibrated authored length.
  final double foreshortening;

  const NuvoArmPose.downStraight({
    required NuvoDirection2D direction,
    this.foreshortening = 1,
  }) : upperDirection = direction,
       lowerDirection = direction;

  const NuvoArmPose.bentOverhead({
    required this.upperDirection,
    required this.lowerDirection,
    this.foreshortening = 1,
  });

  NuvoArmPose mirrored() => NuvoArmPose(
    upperDirection: upperDirection.mirrored(),
    lowerDirection: lowerDirection.mirrored(),
    foreshortening: foreshortening,
  );

  NuvoArmPose lerp(NuvoArmPose other, double t) => NuvoArmPose(
    upperDirection: _lerpDirection(upperDirection, other.upperDirection, t),
    lowerDirection: _lerpDirection(lowerDirection, other.lowerDirection, t),
    foreshortening: _lerp(foreshortening, other.foreshortening, t),
  );
}

class NuvoLegPose {
  const NuvoLegPose({
    required this.upperDirection,
    required this.lowerDirection,
    this.foreshortening = 1,
  });

  final NuvoDirection2D upperDirection;
  final NuvoDirection2D lowerDirection;
  final double foreshortening;

  const NuvoLegPose.standing({
    required NuvoDirection2D direction,
    this.foreshortening = 1,
  }) : upperDirection = direction,
       lowerDirection = direction;

  const NuvoLegPose.spread({
    required this.upperDirection,
    required this.lowerDirection,
    this.foreshortening = 1,
  });

  NuvoLegPose lerp(NuvoLegPose other, double t) => NuvoLegPose(
    upperDirection: _lerpDirection(upperDirection, other.upperDirection, t),
    lowerDirection: _lerpDirection(lowerDirection, other.lowerDirection, t),
    foreshortening: _lerp(foreshortening, other.foreshortening, t),
  );
}

class NuvoHumanPose {
  const NuvoHumanPose({
    required this.torsoLean,
    required this.leftArm,
    required this.rightArm,
    required this.leftLeg,
    required this.rightLeg,
    this.rootYOffset = 0,
  });

  final double torsoLean;
  final NuvoArmPose leftArm;
  final NuvoArmPose rightArm;
  final NuvoLegPose leftLeg;
  final NuvoLegPose rightLeg;
  final double rootYOffset;

  static const _closedLeftArm = NuvoDirection2D(-0.148, 0.989);
  static const _closedRightArm = NuvoDirection2D(0.148, 0.989);
  static const _closedLeftLeg = NuvoDirection2D(-0.078, 0.997);
  static const _closedRightLeg = NuvoDirection2D(0.078, 0.997);
  static const _openLeftUpper = NuvoDirection2D(-0.70, -0.70);
  static const _openLeftLower = NuvoDirection2D(0.40, -0.92);
  static const _openRightUpper = NuvoDirection2D(0.70, -0.70);
  static const _openRightLower = NuvoDirection2D(-0.40, -0.92);
  static const _openLeftLeg = NuvoDirection2D(-0.707, 0.707);
  static const _openRightLeg = NuvoDirection2D(0.707, 0.707);

  static const jumpingJackClosed = NuvoHumanPose(
    torsoLean: 0,
    leftArm: NuvoArmPose.downStraight(direction: _closedLeftArm),
    rightArm: NuvoArmPose.downStraight(direction: _closedRightArm),
    leftLeg: NuvoLegPose.standing(direction: _closedLeftLeg),
    rightLeg: NuvoLegPose.standing(direction: _closedRightLeg),
  );

  static const jumpingJackOpen = NuvoHumanPose(
    torsoLean: 0,
    leftArm: NuvoArmPose.bentOverhead(
      upperDirection: _openLeftUpper,
      lowerDirection: _openLeftLower,
    ),
    rightArm: NuvoArmPose.bentOverhead(
      upperDirection: _openRightUpper,
      lowerDirection: _openRightLower,
    ),
    leftLeg: NuvoLegPose.spread(
      upperDirection: _openLeftLeg,
      lowerDirection: _openLeftLeg,
    ),
    rightLeg: NuvoLegPose.spread(
      upperDirection: _openRightLeg,
      lowerDirection: _openRightLeg,
    ),
  );

  NuvoHumanPose lerp(NuvoHumanPose other, double t) => NuvoHumanPose(
    torsoLean: _lerp(torsoLean, other.torsoLean, t),
    leftArm: leftArm.lerp(other.leftArm, t),
    rightArm: rightArm.lerp(other.rightArm, t),
    leftLeg: leftLeg.lerp(other.leftLeg, t),
    rightLeg: rightLeg.lerp(other.rightLeg, t),
    rootYOffset: _lerp(rootYOffset, other.rootYOffset, t),
  );
}

NuvoDirection2D _lerpDirection(
  NuvoDirection2D a,
  NuvoDirection2D b,
  double t,
) => NuvoDirection2D(_lerp(a.x, b.x, t), _lerp(a.y, b.y, t));

double _lerp(double a, double b, double t) {
  final amount = t.isFinite ? t.clamp(0.0, 1.0) : 0.0;
  return a + (b - a) * amount;
}
