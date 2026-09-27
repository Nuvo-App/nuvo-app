import '../../domain/motion_activity.dart';
import 'jumping_jack_preview_sequence.dart';
import 'nuvo_rive_rig_calibration.dart';
import 'rive_pose_frame.dart';
import 'side_rig_movement_sequences.dart';

/// A runtime pose sequence for a pre-verification Rive preview.
///
/// These poses describe the same observable movement phases that Nuvo's live
/// validators look for. They are illustrative only; the camera verifier never
/// consumes these values.
abstract class RiveMovementSequence {
  RiveMovementSequence({required this.duration});

  final Duration duration;

  RivePoseFrame poseAt(double normalizedTime);
}

const _rivePreviewActivities = {
  MotionActivityType.jumpingJacks,
  MotionActivityType.lunges,
  MotionActivityType.armRaises,
  MotionActivityType.runningInPlace,
  MotionActivityType.treadmillRunning,
  MotionActivityType.marchingInPlace,
};

bool hasRiveMovementPreview(MotionActivityType type) =>
    _rivePreviewActivities.contains(type) || hasSideRigMovementPreview(type);

RiveMovementSequence riveMovementSequenceFor(MotionActivityType type) {
  switch (type) {
    case MotionActivityType.jumpingJacks:
      return _JumpingJackSequenceAdapter(
        JumpingJackPreviewSequence(
          closed: _pose(),
          open: _pose(
            leftShoulderAngle: 145,
            leftElbowAngle: 72,
            rightShoulderAngle: -145,
            rightElbowAngle: -72,
            leftHipAngle: 45,
            rightHipAngle: -45,
            rootYOffset: -14,
          ),
        ),
      );
    case MotionActivityType.lunges:
      return _LungesSequence();
    case MotionActivityType.armRaises:
      return _ArmRaisesSequence();
    case MotionActivityType.runningInPlace:
      return _GaitSequence(
        duration: const Duration(milliseconds: 900),
        kneeLift: 70,
        kneeBend: 55,
      );
    case MotionActivityType.treadmillRunning:
      return _GaitSequence(
        duration: const Duration(milliseconds: 900),
        kneeLift: 70,
        kneeBend: 55,
      );
    case MotionActivityType.marchingInPlace:
      return _GaitSequence(
        duration: const Duration(milliseconds: 1250),
        kneeLift: 92,
        kneeBend: 72,
      );
    default:
      throw ArgumentError.value(type, 'type', 'No Rive preview is defined');
  }
}

class _JumpingJackSequenceAdapter extends RiveMovementSequence {
  _JumpingJackSequenceAdapter(this._sequence)
    : super(duration: JumpingJackPreviewSequence.duration);

  final JumpingJackPreviewSequence _sequence;

  @override
  RivePoseFrame poseAt(double normalizedTime) =>
      _sequence.poseAt(normalizedTime);
}

/// Smoothly interpolates semantic key poses. The keyframes intentionally land
/// on validator-friendly states instead of trying to imitate camera landmarks.
class _KeyframeSequence extends RiveMovementSequence {
  _KeyframeSequence({required super.duration, required this.keyframes});

  final List<RivePoseFrame> keyframes;

  @override
  RivePoseFrame poseAt(double normalizedTime) {
    final t = normalizedTime.isFinite
        ? normalizedTime - normalizedTime.floorToDouble()
        : 0.0;
    final segments = keyframes.length - 1;
    final scaled = t * segments;
    final index = scaled.floor().clamp(0, segments - 1);
    final local = _smoothstep(scaled - index);
    return keyframes[index].lerp(keyframes[index + 1], local);
  }
}

/// Lunges: standing → right lunge → standing → left lunge → standing.
///
/// The active poses separate the knees and bend only the forward leg, matching
/// the production lunge definition's knee-separation and <=118° gate.
class _LungesSequence extends _KeyframeSequence {
  _LungesSequence()
    : super(
        duration: const Duration(milliseconds: 2200),
        keyframes: [_standing, _rightLunge, _standing, _leftLunge, _standing],
      );

  static final _standing = _pose();
  static final _rightLunge = _pose(
    leftHipAngle: 10,
    rightHipAngle: -25,
    rightKneeAngle: -72,
  );
  static final _leftLunge = _pose(
    leftHipAngle: 25,
    leftKneeAngle: 72,
    rightHipAngle: -10,
  );
}

/// Arm Raises: both hands travel above the shoulder line and return together.
class _ArmRaisesSequence extends _KeyframeSequence {
  _ArmRaisesSequence()
    : super(
        duration: const Duration(milliseconds: 1800),
        keyframes: [_standing, _raised, _standing],
      );

  static final _standing = _pose();
  static final _raised = _pose(
    leftShoulderAngle: 115,
    leftElbowAngle: 14,
    rightShoulderAngle: -115,
    rightElbowAngle: -14,
  );
}

/// Running/treadmill/marching use alternating lower-body phases. The two
/// running activities deliberately share a profile because their validators
/// use the same body-relative alternating gait signal.
class _GaitSequence extends _KeyframeSequence {
  _GaitSequence({
    required super.duration,
    required this.kneeLift,
    required this.kneeBend,
  }) : super(keyframes: [_standing]);

  final double kneeLift;
  final double kneeBend;

  static final _standing = _pose();

  @override
  RivePoseFrame poseAt(double normalizedTime) {
    final t = normalizedTime.isFinite
        ? normalizedTime - normalizedTime.floorToDouble()
        : 0.0;
    final phase = t * 3;
    final side = phase.floor().clamp(0, 2);
    final local = _smoothstep(phase - side);
    final left = _liftedLeft;
    final right = _liftedRight;
    if (side == 0) {
      return _standing.lerp(left, local);
    }
    if (side == 1) return left.lerp(right, local);
    return right.lerp(_standing, local);
  }

  late final RivePoseFrame _liftedLeft = _pose(
    leftHipAngle: kneeLift,
    leftKneeAngle: kneeBend,
  );

  late final RivePoseFrame _liftedRight = _pose(
    rightHipAngle: -kneeLift,
    rightKneeAngle: -kneeBend,
  );
}

RivePoseFrame _pose({
  double leftShoulderAngle = 0,
  double leftElbowAngle = 0,
  double rightShoulderAngle = 0,
  double rightElbowAngle = 0,
  double leftHipAngle = 0,
  double leftKneeAngle = 0,
  double rightHipAngle = 0,
  double rightKneeAngle = 0,
  double rootYOffset = 0,
}) {
  final frame = NuvoRiveRigCalibration.standing.resolve(
    RigPoseOffset(
      leftShoulderAngle: leftShoulderAngle,
      leftElbowAngle: leftElbowAngle,
      rightShoulderAngle: rightShoulderAngle,
      rightElbowAngle: rightElbowAngle,
      leftHipAngle: leftHipAngle,
      leftKneeAngle: leftKneeAngle,
      rightHipAngle: rightHipAngle,
      rightKneeAngle: rightKneeAngle,
    ),
  );
  return frame.copyWith(
    leftUpperArmScale: 92,
    leftLowerArmScale: 92,
    rightUpperArmScale: 92,
    rightLowerArmScale: 92,
    rootYOffset: rootYOffset,
  );
}

double _smoothstep(double t) {
  final amount = t.clamp(0.0, 1.0);
  return amount * amount * (3 - 2 * amount);
}
