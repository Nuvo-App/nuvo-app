import '../../domain/motion_activity.dart';
import 'side_rig_treadmill_preview.dart';

/// Movements that do not yet have a dedicated front-view Rive sequence.
///
/// These previews are visual guidance only. The camera verifier remains the
/// authority for movement completion and repetition acceptance.
const sideRigMovementPreviewActivities = {
  MotionActivityType.pushUps,
  MotionActivityType.squats,
  MotionActivityType.highKnees,
  MotionActivityType.plankHold,
  MotionActivityType.sumoSquats,
  MotionActivityType.sideLunges,
  MotionActivityType.deepSquats,
  MotionActivityType.squatJacks,
  MotionActivityType.jumpSquats,
  MotionActivityType.lungeJumps,
  MotionActivityType.walkingInPlace,
  MotionActivityType.buttKicks,
  MotionActivityType.mountainClimbers,
  MotionActivityType.burpees,
  MotionActivityType.stepUps,
  MotionActivityType.calfRaises,
  MotionActivityType.lateralSteps,
  MotionActivityType.basketballShot,
};

bool hasSideRigMovementPreview(MotionActivityType type) =>
    sideRigMovementPreviewActivities.contains(type);

SideRigMovementSequence sideRigMovementSequenceFor(MotionActivityType type) {
  switch (type) {
    case MotionActivityType.pushUps:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1800),
        keyframes: [_standing, _pushUpDown, _standing],
      );
    case MotionActivityType.squats:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1800),
        keyframes: [_standing, _squat, _standing],
      );
    case MotionActivityType.highKnees:
      return _alternatingGait(
        duration: const Duration(milliseconds: 900),
        hipLift: 132,
        kneeBend: 72,
      );
    case MotionActivityType.plankHold:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1600),
        keyframes: [_standing, _plank, _plank, _standing],
      );
    case MotionActivityType.sumoSquats:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1900),
        keyframes: [_standing, _sumoSquat, _standing],
      );
    case MotionActivityType.sideLunges:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 2200),
        keyframes: [_standing, _sideLungeForward, _standing, _standing],
      );
    case MotionActivityType.deepSquats:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 2200),
        keyframes: [_standing, _deepSquat, _standing],
      );
    case MotionActivityType.squatJacks:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1700),
        keyframes: [_standing, _squatJack, _standing],
      );
    case MotionActivityType.jumpSquats:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1500),
        keyframes: [_standing, _squat, _jump, _standing],
      );
    case MotionActivityType.lungeJumps:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1700),
        keyframes: [_standing, _splitLeft, _jump, _splitRight, _standing],
      );
    case MotionActivityType.walkingInPlace:
      return _alternatingGait(
        duration: const Duration(milliseconds: 1250),
        hipLift: 112,
        kneeBend: 42,
      );
    case MotionActivityType.buttKicks:
      return _alternatingButtKicks();
    case MotionActivityType.mountainClimbers:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1200),
        keyframes: [_plank, _climberLeft, _plank, _climberRight, _plank],
      );
    case MotionActivityType.burpees:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 2600),
        keyframes: [_standing, _squat, _plank, _squat, _standing],
      );
    case MotionActivityType.stepUps:
      return _alternatingGait(
        duration: const Duration(milliseconds: 1400),
        hipLift: 118,
        kneeBend: 48,
      );
    case MotionActivityType.calfRaises:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1200),
        keyframes: [_standing, _calfRaise, _standing],
      );
    case MotionActivityType.lateralSteps:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1300),
        keyframes: [_standing, _lateralStep, _standing, _lateralStepBack],
      );
    case MotionActivityType.basketballShot:
      return _KeyframeSideSequence(
        duration: const Duration(milliseconds: 1800),
        keyframes: [_standing, _shotCrouch, _shotRelease, _standing],
      );
    default:
      throw ArgumentError.value(type, 'type', 'No side Rive preview exists');
  }
}

abstract class SideRigMovementSequence {
  const SideRigMovementSequence({required this.duration});

  final Duration duration;

  SideRigPose poseAt(double normalizedTime);
}

class _KeyframeSideSequence extends SideRigMovementSequence {
  const _KeyframeSideSequence({required super.duration, required this.keyframes});

  final List<SideRigPose> keyframes;

  @override
  SideRigPose poseAt(double normalizedTime) {
    final t = normalizedTime.isFinite
        ? normalizedTime - normalizedTime.floorToDouble()
        : 0.0;
    final segments = keyframes.length - 1;
    final scaled = t * segments;
    final index = scaled.floor().clamp(0, segments - 1);
    final local = _smoothstep(scaled - index);
    final pose = keyframes[index].lerp(keyframes[index + 1], local);
    return poseWithBounce(pose, t);
  }
}

class _AlternatingSideSequence extends SideRigMovementSequence {
  const _AlternatingSideSequence({required super.duration, required this.left, required this.right});

  final SideRigPose left;
  final SideRigPose right;

  @override
  SideRigPose poseAt(double normalizedTime) {
    final t = normalizedTime.isFinite
        ? normalizedTime - normalizedTime.floorToDouble()
        : 0.0;
    final phase = t * 4;
    final index = phase.floor().clamp(0, 3);
    final local = _smoothstep(phase - index);
    final pose = switch (index) {
      0 => _standing.lerp(left, local),
      1 => left.lerp(right, local),
      2 => right.lerp(_standing, local),
      _ => _standing.lerp(left, local),
    };
    return poseWithBounce(pose, t);
  }
}

SideRigMovementSequence _alternatingGait({
  required Duration duration,
  required double hipLift,
  required double kneeBend,
}) => _AlternatingSideSequence(
  duration: duration,
  left: _gaitPose(hipLift: hipLift, kneeBend: kneeBend, left: true),
  right: _gaitPose(hipLift: hipLift, kneeBend: kneeBend, left: false),
);

SideRigMovementSequence _alternatingButtKicks() => _AlternatingSideSequence(
  duration: const Duration(milliseconds: 950),
  left: _pose(
    frontHipAngle: 82,
    backHipAngle: 98,
    frontKneeAngle: 86,
    backKneeAngle: 12,
    frontShoulderAngle: 68,
    frontElbowAngle: -34,
    backShoulderAngle: 112,
    backElbowAngle: 34,
  ),
  right: _pose(
    frontHipAngle: 98,
    backHipAngle: 82,
    frontKneeAngle: 12,
    backKneeAngle: 86,
    frontShoulderAngle: 112,
    frontElbowAngle: 34,
    backShoulderAngle: 68,
    backElbowAngle: -34,
  ),
);

SideRigPose _gaitPose({
  required double hipLift,
  required double kneeBend,
  required bool left,
}) => left
    ? _pose(
        frontHipAngle: hipLift,
        frontKneeAngle: kneeBend,
        backHipAngle: 52,
        backKneeAngle: 24,
        frontShoulderAngle: 62,
        frontElbowAngle: -38,
        backShoulderAngle: 118,
        backElbowAngle: 38,
      )
    : _pose(
        frontHipAngle: 52,
        frontKneeAngle: 24,
        backHipAngle: hipLift,
        backKneeAngle: kneeBend,
        frontShoulderAngle: 118,
        frontElbowAngle: 38,
        backShoulderAngle: 62,
        backElbowAngle: -38,
      );

final _standing = SideRigPose.base;
final _squat = _pose(
  torsoAngle: 12,
  frontHipAngle: 66,
  frontKneeAngle: 58,
  backHipAngle: 114,
  backKneeAngle: -58,
);
final _deepSquat = _pose(
  torsoAngle: 18,
  frontHipAngle: 54,
  frontKneeAngle: 78,
  backHipAngle: 126,
  backKneeAngle: -78,
);
final _sumoSquat = _pose(
  torsoAngle: 8,
  frontHipAngle: 58,
  frontKneeAngle: 64,
  backHipAngle: 122,
  backKneeAngle: -64,
);
final _squatJack = _pose(
  frontHipAngle: 66,
  frontKneeAngle: 48,
  backHipAngle: 114,
  backKneeAngle: -48,
  frontShoulderAngle: 70,
  frontElbowAngle: -20,
  backShoulderAngle: 110,
  backElbowAngle: 20,
);
final _jump = _pose(
  frontHipAngle: 84,
  frontKneeAngle: 14,
  backHipAngle: 96,
  backKneeAngle: -14,
  rootYOffset: -14,
);
final _pushUpDown = _pose(
  torsoAngle: -90,
  frontHipAngle: 86,
  backHipAngle: 94,
  frontShoulderAngle: 112,
  frontElbowAngle: 54,
  backShoulderAngle: 68,
  backElbowAngle: -54,
);
final _plank = _pose(
  torsoAngle: -90,
  frontHipAngle: 90,
  backHipAngle: 90,
  frontShoulderAngle: 90,
  backShoulderAngle: 90,
);
final _splitLeft = _pose(
  frontHipAngle: 48,
  frontKneeAngle: 44,
  backHipAngle: 132,
  backKneeAngle: -22,
);
final _splitRight = _pose(
  frontHipAngle: 132,
  frontKneeAngle: 22,
  backHipAngle: 48,
  backKneeAngle: -44,
);
final _sideLungeForward = _pose(
  frontHipAngle: 44,
  frontKneeAngle: 68,
  backHipAngle: 136,
  backKneeAngle: -12,
  torsoAngle: 10,
);
final _climberLeft = _pose(
  torsoAngle: -90,
  frontHipAngle: 58,
  frontKneeAngle: 74,
  backHipAngle: 98,
  backKneeAngle: -8,
);
final _climberRight = _pose(
  torsoAngle: -90,
  frontHipAngle: 98,
  frontKneeAngle: 8,
  backHipAngle: 58,
  backKneeAngle: -74,
);
final _calfRaise = _pose(rootYOffset: -5);
final _lateralStep = _pose(
  frontHipAngle: 78,
  frontKneeAngle: 26,
  backHipAngle: 102,
  backKneeAngle: -26,
  rootYOffset: -3,
);
final _lateralStepBack = _pose(
  frontHipAngle: 102,
  frontKneeAngle: 26,
  backHipAngle: 78,
  backKneeAngle: -26,
  rootYOffset: -3,
);
final _shotCrouch = _pose(
  torsoAngle: 8,
  frontHipAngle: 70,
  frontKneeAngle: 54,
  backHipAngle: 110,
  backKneeAngle: -54,
);
final _shotRelease = _pose(
  frontShoulderAngle: 26,
  frontElbowAngle: -36,
  backShoulderAngle: 154,
  backElbowAngle: 36,
  rootYOffset: -10,
);

SideRigPose _pose({
  double torsoAngle = 0,
  double frontShoulderAngle = 90,
  double frontElbowAngle = 0,
  double backShoulderAngle = 90,
  double backElbowAngle = 0,
  double frontHipAngle = 90,
  double frontKneeAngle = 0,
  double backHipAngle = 90,
  double backKneeAngle = 0,
  double rootYOffset = 0,
}) => SideRigPose(
  torsoAngle: torsoAngle,
  frontShoulderAngle: frontShoulderAngle,
  frontElbowAngle: frontElbowAngle,
  backShoulderAngle: backShoulderAngle,
  backElbowAngle: backElbowAngle,
  frontHipAngle: frontHipAngle,
  frontKneeAngle: frontKneeAngle,
  backHipAngle: backHipAngle,
  backKneeAngle: backKneeAngle,
  frontUpperArmScale: 100,
  frontLowerArmScale: 100,
  backUpperArmScale: 100,
  backLowerArmScale: 100,
  frontUpperLegScale: 100,
  frontLowerLegScale: 100,
  backUpperLegScale: 100,
  backLowerLegScale: 100,
  torsoScaleY: 100,
  rootYOffset: rootYOffset,
);

SideRigPose poseWithBounce(SideRigPose pose, double time) {
  final bounce = pose.rootYOffset == 0
      ? -4 * (1 - (2 * time - 1).abs())
      : pose.rootYOffset;
  return SideRigPose(
    torsoAngle: pose.torsoAngle,
    frontShoulderAngle: pose.frontShoulderAngle,
    frontElbowAngle: pose.frontElbowAngle,
    backShoulderAngle: pose.backShoulderAngle,
    backElbowAngle: pose.backElbowAngle,
    frontHipAngle: pose.frontHipAngle,
    frontKneeAngle: pose.frontKneeAngle,
    backHipAngle: pose.backHipAngle,
    backKneeAngle: pose.backKneeAngle,
    frontUpperArmScale: pose.frontUpperArmScale,
    frontLowerArmScale: pose.frontLowerArmScale,
    backUpperArmScale: pose.backUpperArmScale,
    backLowerArmScale: pose.backLowerArmScale,
    frontUpperLegScale: pose.frontUpperLegScale,
    frontLowerLegScale: pose.frontLowerLegScale,
    backUpperLegScale: pose.backUpperLegScale,
    backLowerLegScale: pose.backLowerLegScale,
    torsoScaleY: pose.torsoScaleY,
    rootYOffset: bounce,
  );
}

double _smoothstep(double t) {
  final amount = t.clamp(0.0, 1.0);
  return amount * amount * (3 - 2 * amount);
}
