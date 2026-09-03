import 'dart:math' as math;

import '../data/ai_motion_models.dart';
import '../domain/motion_activity.dart';
import 'airborne_state_tracker.dart';
import 'multi_phase_sequence_tracker.dart';
import 'preset_motion/multi_phase_definitions.dart';

enum MovementType {
  pushups,
  squats,
  jumpingJacks,
  plank,
  lunges,
  highKnees,
  armRaises,
  sumoSquats,
  sideLunges,
  deepSquats,
  squatJacks,
  jumpSquats,
  lungeJumps,
  unsupported,
}

enum MovementPhase { unknown, start, active }

enum MovementVerificationState {
  loadingCamera,
  waitingForBody,
  ready,
  verifying,
  targetComplete,
  tryAgain,
  unsupportedMovement,
}

class MovementDefinition {
  const MovementDefinition({
    required this.type,
    required this.activity,
    required this.title,
    required this.unit,
    required this.defaultTarget,
    this.isHold = false,
  });

  final MovementType type;
  final AiMotionActivity activity;
  final String title;
  final String unit;
  final int defaultTarget;
  final bool isHold;

  String targetLabel(int target) => isHold ? '$target sec' : '$target $unit';
}

const supportedMovementDefinitions = [
  MovementDefinition(
    type: MovementType.pushups,
    activity: AiMotionActivity.pushUps,
    title: 'Pushups',
    unit: 'pushups',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.squats,
    activity: AiMotionActivity.squats,
    title: 'Squats',
    unit: 'squats',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.jumpingJacks,
    activity: AiMotionActivity.jumpingJacks,
    title: 'Jumping jacks',
    unit: 'jumping jacks',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.plank,
    activity: AiMotionActivity.plankHold,
    title: 'Plank',
    unit: 'seconds',
    defaultTarget: 20,
    isHold: true,
  ),
  MovementDefinition(
    type: MovementType.lunges,
    activity: AiMotionActivity.lunges,
    title: 'Lunges',
    unit: 'lunges',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.highKnees,
    activity: AiMotionActivity.highKnees,
    title: 'High knees',
    unit: 'high knees',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.armRaises,
    activity: AiMotionActivity.armRaises,
    title: 'Arm raises',
    unit: 'arm raises',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.sumoSquats,
    activity: AiMotionActivity.sumoSquats,
    title: 'Sumo squats',
    unit: 'sumo squats',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.sideLunges,
    activity: AiMotionActivity.sideLunges,
    title: 'Side lunges',
    unit: 'side lunges',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.deepSquats,
    activity: AiMotionActivity.deepSquats,
    title: 'Deep squats',
    unit: 'deep squats',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.squatJacks,
    activity: AiMotionActivity.squatJacks,
    title: 'Squat jacks',
    unit: 'squat jacks',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.jumpSquats,
    activity: AiMotionActivity.jumpSquats,
    title: 'Jump squats',
    unit: 'jump squats',
    defaultTarget: 10,
  ),
  MovementDefinition(
    type: MovementType.lungeJumps,
    activity: AiMotionActivity.lungeJumps,
    title: 'Lunge jumps',
    unit: 'lunge jumps',
    defaultTarget: 10,
  ),
];

MovementDefinition? movementDefinitionForActivity(AiMotionActivity activity) {
  for (final definition in supportedMovementDefinitions) {
    if (definition.activity == activity) return definition;
  }
  return null;
}

/// Resolves a [MotionActivityType] (domain identity) to the corresponding
/// runtime [MovementDefinition]. This is the canonical bridge between the
/// catalog identity and the validator runtime — no string matching required.
MovementDefinition? movementDefinitionForType(MotionActivityType type) {
  final activity = _aiMotionActivityForType(type);
  if (activity == null) return null;
  return movementDefinitionForActivity(activity);
}

AiMotionActivity? _aiMotionActivityForType(MotionActivityType type) {
  return switch (type) {
    MotionActivityType.pushUps => AiMotionActivity.pushUps,
    MotionActivityType.jumpingJacks => AiMotionActivity.jumpingJacks,
    MotionActivityType.squats => AiMotionActivity.squats,
    MotionActivityType.lunges => AiMotionActivity.lunges,
    MotionActivityType.highKnees => AiMotionActivity.highKnees,
    MotionActivityType.armRaises => AiMotionActivity.armRaises,
    MotionActivityType.plankHold => AiMotionActivity.plankHold,
    MotionActivityType.sumoSquats => AiMotionActivity.sumoSquats,
    MotionActivityType.sideLunges => AiMotionActivity.sideLunges,
    MotionActivityType.deepSquats => AiMotionActivity.deepSquats,
    MotionActivityType.squatJacks => AiMotionActivity.squatJacks,
    MotionActivityType.jumpSquats => AiMotionActivity.jumpSquats,
    MotionActivityType.lungeJumps => AiMotionActivity.lungeJumps,
  };
}

class NuvoVerifyOutput {
  const NuvoVerifyOutput({
    required this.selectedMovement,
    required this.state,
    required this.count,
    required this.holdSeconds,
    required this.target,
    required this.confidence,
    required this.feedbackMessage,
    required this.completed,
    required this.debugValues,
    required this.validatorState,
    required this.failedRuleReason,
  });

  final MovementDefinition selectedMovement;
  final MovementVerificationState state;
  final int count;
  final int holdSeconds;
  final int target;
  final double confidence;
  final String feedbackMessage;
  final bool completed;
  final Map<String, double> debugValues;
  final String validatorState;
  final String failedRuleReason;
}

class NuvoVerifyEngine {
  NuvoVerifyEngine({required MovementDefinition movement, required int target})
    : _movement = movement,
      _validator = createMotionValidator(movement.activity, target);

  MovementDefinition _movement;
  MotionValidator _validator;

  MovementDefinition get movement => _movement;
  MotionValidator get validator => _validator;
  int get targetValue => _validator.targetValue;
  int get currentValue => _validator.currentValue;
  bool get fullBodyVisible => _validator.fullBodyVisible;
  String get validatorState => _validator.stateLabel;
  String get failedRuleReason => _validator.failedRuleReason;

  void selectMovement(MovementDefinition movement, int target) {
    _movement = movement;
    _validator = createMotionValidator(movement.activity, target);
  }

  void start() => _validator.start();
  AiMotionResult finish() => _validator.finish();

  NuvoVerifyOutput update(NuvoPoseFrame frame) {
    _validator.update(frame);
    return output(MovementVerificationState.verifying);
  }

  NuvoVerifyOutput output(MovementVerificationState state) {
    final value = _validator.currentValue;
    final completed = value >= _validator.targetValue;
    final nextState = completed
        ? MovementVerificationState.targetComplete
        : state;
    return NuvoVerifyOutput(
      selectedMovement: _movement,
      state: nextState,
      count: _movement.isHold ? 0 : value,
      holdSeconds: _movement.isHold ? value : 0,
      target: _validator.targetValue,
      confidence: _validator.confidence,
      feedbackMessage: completed
          ? 'Target complete.'
          : _validator.fullBodyVisible
          ? _validator.coachingText
          : 'Position your full body in frame.',
      completed: completed,
      debugValues: _validator.debugValues,
      validatorState: _validator.stateLabel,
      failedRuleReason: _validator.failedRuleReason,
    );
  }
}

class MotionValidationUpdate {
  const MotionValidationUpdate({
    required this.currentValue,
    required this.targetValue,
    required this.isVerified,
    required this.statusText,
    required this.coachingText,
    required this.framesAnalyzed,
    required this.validPoseFrames,
    required this.durationMs,
  });

  final int currentValue;
  final int targetValue;
  final bool isVerified;
  final String statusText;
  final String coachingText;
  final int framesAnalyzed;
  final int validPoseFrames;
  final int durationMs;
}

abstract class MotionValidator {
  MotionValidator({required this.targetValue});

  final int targetValue;

  AiMotionActivity get activity;
  int get currentValue;
  int get framesAnalyzed;
  int get validPoseFrames;
  int get durationMs;
  bool get fullBodyVisible;
  String get statusText;
  String get coachingText;
  double get confidence;
  Map<String, double> get debugValues;
  String get stateLabel;
  String get failedRuleReason;

  void start();
  MotionValidationUpdate update(NuvoPoseFrame frame);
  AiMotionResult finish();
  void reset() => start();

  MotionValidationUpdate snapshot() => MotionValidationUpdate(
    currentValue: currentValue,
    targetValue: targetValue,
    isVerified: currentValue >= targetValue && validPoseFrames > 0,
    statusText: statusText,
    coachingText: coachingText,
    framesAnalyzed: framesAnalyzed,
    validPoseFrames: validPoseFrames,
    durationMs: durationMs,
  );
}

/// Authoritative validator factory for each preset movement.
/// This switch and [supportedMovementDefinitions] must stay in sync — every
/// entry in [supportedMovementDefinitions] must have a case here.
/// [verifyValidatorDispatchComplete] verifies this invariant.
MotionValidator createMotionValidator(
  AiMotionActivity activity,
  int targetValue,
) => switch (activity) {
  AiMotionActivity.pushUps => PushupsValidator(targetValue: targetValue),
  AiMotionActivity.jumpingJacks => ConfigurableRepValidator(
    definition: jumpingJackRepDefinition,
    targetValue: targetValue,
  ),
  AiMotionActivity.squats => ConfigurableRepValidator(
    definition: squatRepDefinition,
    targetValue: targetValue,
  ),
  AiMotionActivity.lunges => ConfigurableRepValidator(
    definition: lungeRepDefinition,
    targetValue: targetValue,
  ),
  AiMotionActivity.highKnees => HighKneesValidator(targetValue: targetValue),
  AiMotionActivity.armRaises => ArmRaisesValidator(targetValue: targetValue),
  AiMotionActivity.plankHold => PlankHoldValidator(targetValue: targetValue),
  AiMotionActivity.sumoSquats => ConfigurableRepValidator(
    definition: sumoSquatRepDefinition,
    targetValue: targetValue,
  ),
  AiMotionActivity.sideLunges => ConfigurableRepValidator(
    definition: sideLungeRepDefinition,
    targetValue: targetValue,
  ),
  AiMotionActivity.deepSquats => ConfigurableRepValidator(
    definition: deepSquatRepDefinition,
    targetValue: targetValue,
  ),
  AiMotionActivity.squatJacks => ConfigurableRepValidator(
    definition: squatJackRepDefinition,
    targetValue: targetValue,
  ),
  AiMotionActivity.jumpSquats => MultiPhaseSequenceValidator(
    activity: AiMotionActivity.jumpSquats,
    targetValue: targetValue,
    definitions: (airborne) => [buildJumpSquatDefinition(airborne)],
    statusText: 'Tracking jump squats',
    coachingTextActive: 'Squat down, jump up, land soft',
    coachingTextIncomplete: 'Full body needed',
  ),
  AiMotionActivity.lungeJumps => MultiPhaseSequenceValidator(
    activity: AiMotionActivity.lungeJumps,
    targetValue: targetValue,
    definitions: buildLungeJumpDefinitions,
    statusText: 'Tracking lunge jumps',
    coachingTextActive: 'Lunge, jump, switch legs',
    coachingTextIncomplete: 'Full body needed',
  ),
};

/// Verifies that every [supportedMovementDefinitions] entry has a matching
/// case in [createMotionValidator]. Throws if a movement is registered in
/// the definitions list but has no validator constructor.
/// Call this from tests to catch registration drift.
void verifyValidatorDispatchComplete() {
  for (final definition in supportedMovementDefinitions) {
    createMotionValidator(definition.activity, 1);
  }
}

class RepCounterStateMachine {
  MovementPhase _stableState = MovementPhase.unknown;
  MovementPhase _candidateState = MovementPhase.unknown;
  int _candidateFrames = 0;
  bool _hitActive = false;
  int _count = 0;

  int get count => _count;
  MovementPhase get stableState => _stableState;

  void reset() {
    _stableState = MovementPhase.unknown;
    _candidateState = MovementPhase.unknown;
    _candidateFrames = 0;
    _hitActive = false;
    _count = 0;
  }

  void update(MovementPhase measuredState, {int stableFrames = 3}) {
    if (measuredState == MovementPhase.unknown) return;
    if (measuredState == _candidateState) {
      _candidateFrames++;
    } else {
      _candidateState = measuredState;
      _candidateFrames = 1;
    }
    if (_candidateFrames < stableFrames || measuredState == _stableState) {
      return;
    }

    final previousState = _stableState;
    _stableState = measuredState;
    if (previousState == MovementPhase.start &&
        measuredState == MovementPhase.active) {
      _hitActive = true;
      return;
    }
    if (previousState == MovementPhase.active &&
        measuredState == MovementPhase.start &&
        _hitActive) {
      _count++;
      _hitActive = false;
    }
  }
}

class HoldTimerStateMachine {
  int _validHoldMs = 0;
  DateTime? _lastValidFrameAt;

  int get seconds => (_validHoldMs / 1000).floor();

  void reset() {
    _validHoldMs = 0;
    _lastValidFrameAt = null;
  }

  void update({required DateTime now, required bool valid}) {
    if (!valid) {
      _lastValidFrameAt = null;
      return;
    }
    if (_lastValidFrameAt != null) {
      final delta = now.difference(_lastValidFrameAt!).inMilliseconds;
      if (delta > 0 && delta < 500) _validHoldMs += delta;
    }
    _lastValidFrameAt = now;
  }
}

class PoseFeatureExtractor {
  const PoseFeatureExtractor(this.frame);

  final NuvoPoseFrame frame;

  double get shoulderY => _averageY('leftShoulder', 'rightShoulder');
  double get hipY => _averageY('leftHip', 'rightHip');
  double get kneeY => _averageY('leftKnee', 'rightKnee');
  double get ankleY => _averageY('leftAnkle', 'rightAnkle');
  double get shoulderWidth => _distanceX('leftShoulder', 'rightShoulder');
  double get hipWidth => _distanceX('leftHip', 'rightHip');
  double get ankleWidth => _distanceX('leftAnkle', 'rightAnkle');
  double get bodyWidth => math.max(shoulderWidth, hipWidth).clamp(0.08, 0.6);
  double get torsoHeight => (hipY - shoulderY).abs().clamp(0.12, 0.6);

  bool get wristsAboveShoulders {
    final leftWrist = frame.point('leftWrist')!;
    final rightWrist = frame.point('rightWrist')!;
    return leftWrist.y < shoulderY - 0.03 && rightWrist.y < shoulderY - 0.03;
  }

  bool get wristsNearBody {
    final leftWrist = frame.point('leftWrist')!;
    final rightWrist = frame.point('rightWrist')!;
    return leftWrist.y > shoulderY - 0.01 &&
        rightWrist.y > shoulderY - 0.01 &&
        leftWrist.y < hipY + 0.24 &&
        rightWrist.y < hipY + 0.24;
  }

  double elbowAngle({required bool left}) {
    final shoulder = frame.point(left ? 'leftShoulder' : 'rightShoulder')!;
    final elbow = frame.point(left ? 'leftElbow' : 'rightElbow')!;
    final wrist = frame.point(left ? 'leftWrist' : 'rightWrist')!;
    return _angle(shoulder, elbow, wrist);
  }

  double kneeAngle({required bool left}) {
    final hip = frame.point(left ? 'leftHip' : 'rightHip');
    final knee = frame.point(left ? 'leftKnee' : 'rightKnee');
    final ankle = frame.point(left ? 'leftAnkle' : 'rightAnkle');
    if (hip == null || knee == null || ankle == null) return 180;
    return _angle(hip, knee, ankle);
  }

  double hipToKneeRatio() => ((kneeY - hipY) / torsoHeight).clamp(-2.0, 3.0);

  double _averageY(String a, String b) =>
      (frame.point(a)!.y + frame.point(b)!.y) / 2;
  double _distanceX(String a, String b) =>
      (frame.point(a)!.x - frame.point(b)!.x).abs();

  double _angle(NuvoPosePoint a, NuvoPosePoint b, NuvoPosePoint c) {
    final abx = a.x - b.x;
    final aby = a.y - b.y;
    final cbx = c.x - b.x;
    final cby = c.y - b.y;
    final dot = abx * cbx + aby * cby;
    final ab = math.sqrt(abx * abx + aby * aby);
    final cb = math.sqrt(cbx * cbx + cby * cby);
    if (ab == 0 || cb == 0) return 180;
    final cosine = (dot / (ab * cb)).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }
}

abstract class _BaseValidator extends MotionValidator {
  _BaseValidator({required super.targetValue});

  static const validatorVersion = 'nuvo-ai-motion-v2';

  @override
  int framesAnalyzed = 0;
  @override
  int validPoseFrames = 0;
  int invalidPoseFrames = 0;
  DateTime? startedAt;
  double lastVisibilityScore = 0;
  String lastFailureReason = '';

  @override
  int get durationMs => startedAt == null
      ? 0
      : DateTime.now().difference(startedAt!).inMilliseconds;

  @override
  bool get fullBodyVisible => lastVisibilityScore >= 0.70;

  @override
  String get stateLabel => 'tracking';

  @override
  String get failedRuleReason => lastFailureReason;

  List<String> get criticalPoints;

  @override
  void start() {
    framesAnalyzed = 0;
    validPoseFrames = 0;
    invalidPoseFrames = 0;
    startedAt = DateTime.now();
    lastVisibilityScore = 0;
    lastFailureReason = '';
    resetState();
  }

  void resetState();

  @override
  MotionValidationUpdate update(NuvoPoseFrame frame) {
    framesAnalyzed++;
    if (!frame.hasPoints(criticalPoints)) {
      invalidPoseFrames++;
      lastVisibilityScore = 0;
      lastFailureReason = 'missing_landmarks';
      return snapshot();
    }
    validPoseFrames++;
    lastVisibilityScore = _visibilityScore(frame);
    if (!fullBodyVisible) {
      lastFailureReason = 'low_landmark_confidence';
    }
    analyzeValidFrame(frame);
    return snapshot();
  }

  void analyzeValidFrame(NuvoPoseFrame frame);

  @override
  double get confidence {
    if (framesAnalyzed == 0 || validPoseFrames == 0) return 0;
    final validRatio = validPoseFrames / framesAnalyzed;
    final targetRatio = math.min(1.0, currentValue / targetValue);
    final invalidPenalty = math.min(0.25, invalidPoseFrames / framesAnalyzed);
    return (validRatio * 0.58 + targetRatio * 0.42).clamp(
      0.0,
      1.0 - invalidPenalty,
    );
  }

  @override
  Map<String, double> get debugValues => {
    'framesAnalyzed': framesAnalyzed.toDouble(),
    'validPoseFrames': validPoseFrames.toDouble(),
    'visibility': lastVisibilityScore,
  };

  @override
  AiMotionResult finish() {
    final verified =
        currentValue >= targetValue &&
        validPoseFrames > 0 &&
        confidence >= 0.58;
    return AiMotionResult(
      activity: activity,
      targetReps: targetValue,
      detectedReps: currentValue,
      confidence: confidence,
      verificationStatus: verified ? 'ai_verified' : 'ai_failed',
      verificationSummary: verified
          ? 'Detected $currentValue ${activity.label} from live pose tracking.'
          : 'Nuvo detected $currentValue clean ${activity.label} out of $targetValue.',
      framesAnalyzed: framesAnalyzed,
      validPoseFrames: validPoseFrames,
      durationMs: durationMs,
      validatorVersion: validatorVersion,
    );
  }

  double _visibilityScore(NuvoPoseFrame frame) {
    var total = 0.0;
    for (final name in criticalPoints) {
      total += frame.point(name)?.likelihood ?? 0;
    }
    return total / criticalPoints.length;
  }
}

enum _OpenClosedState { unknown, closed, open }

class PushupsValidator extends _BaseValidator {
  PushupsValidator({required super.targetValue});

  // Pose frames arrive asynchronously from the camera. Two corroborating
  // frames catch a fast, real phase without allowing a single noisy frame to
  // count as a rep.
  static const _phaseStableFrames = 2;
  static const _repCooldownFrames = 3;

  final RepCounterStateMachine _counter = RepCounterStateMachine();
  double? _topShoulderY;
  int _cooldownFrames = 0;
  double _lastElbowAngle = 180;
  double _lastShoulderDrop = 0;
  double _lastSymmetryError = 0;
  String _pushupFeedback = 'Position yourself in frame.';

  @override
  AiMotionActivity get activity => AiMotionActivity.pushUps;
  @override
  int get currentValue => math.min(_counter.count, targetValue);
  @override
  String get statusText => 'Tracking pushups';
  @override
  String get coachingText => _pushupFeedback;
  @override
  String get stateLabel =>
      '${_counter.stableState.name}:${_cooldownFrames > 0 ? 'cooldown' : 'ready'}';
  @override
  List<String> get criticalPoints => const [
    'leftShoulder',
    'rightShoulder',
    'leftElbow',
    'rightElbow',
    'leftWrist',
    'rightWrist',
    'leftHip',
    'rightHip',
  ];

  @override
  void resetState() {
    _counter.reset();
    _topShoulderY = null;
    _cooldownFrames = 0;
    _lastElbowAngle = 180;
    _lastShoulderDrop = 0;
    _lastSymmetryError = 0;
    _pushupFeedback = 'Position yourself in frame.';
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final features = PoseFeatureExtractor(frame);
    final leftElbowAngle = features.elbowAngle(left: true);
    final rightElbowAngle = features.elbowAngle(left: false);
    final elbowAngle = (leftElbowAngle + rightElbowAngle) / 2;
    final symmetryError = (leftElbowAngle - rightElbowAngle).abs();
    final shoulderY = features.shoulderY;
    final wristY =
        (frame.point('leftWrist')!.y + frame.point('rightWrist')!.y) / 2;
    final handsBelowShoulders =
        wristY > shoulderY - features.torsoHeight * 0.15;
    final symmetrical = symmetryError < 62;

    _lastElbowAngle = elbowAngle;
    _lastSymmetryError = symmetryError;

    if (!fullBodyVisible) {
      lastFailureReason = 'low_landmark_confidence';
      _pushupFeedback = 'Position yourself in frame.';
      _counter.update(MovementPhase.unknown);
      return;
    }
    if (!_isSafeFraming(frame)) {
      lastFailureReason = 'pushup_framing_too_close';
      _pushupFeedback =
          'Move the camera back so your upper body fits in frame.';
      _counter.update(MovementPhase.unknown);
      return;
    }
    if (!handsBelowShoulders) {
      lastFailureReason = 'hands_not_visible_for_pushup';
      _pushupFeedback = 'Keep your upper body in frame.';
      _counter.update(MovementPhase.unknown);
      return;
    }
    if (!symmetrical) {
      lastFailureReason = 'pushup_asymmetry';
      _pushupFeedback = 'Face the camera.';
      _counter.update(MovementPhase.unknown);
      return;
    }

    if (elbowAngle > 150) {
      _topShoulderY = _topShoulderY == null
          ? shoulderY
          : math.min(_topShoulderY!, shoulderY);
    }
    final topShoulderY = _topShoulderY ?? shoulderY;
    final shoulderDrop = (shoulderY - topShoulderY).clamp(0.0, 1.0);
    _lastShoulderDrop = shoulderDrop;

    final previousCount = _counter.count;
    if (_cooldownFrames > 0) _cooldownFrames--;

    if (elbowAngle > 150) {
      _counter.update(MovementPhase.start, stableFrames: _phaseStableFrames);
      _pushupFeedback = 'Start when ready.';
    } else if (_cooldownFrames == 0 &&
        // A pushup must show both elbow flexion and the torso moving down.
        // Using either signal lets arm-only movement or camera jitter count.
        elbowAngle < 112 &&
        shoulderDrop > features.torsoHeight * 0.16) {
      _counter.update(MovementPhase.active, stableFrames: _phaseStableFrames);
      _pushupFeedback = 'Keep going.';
    } else {
      lastFailureReason = 'pushup_not_low_enough';
      _pushupFeedback = 'Keep going.';
      _counter.update(MovementPhase.unknown);
    }

    if (_counter.count > previousCount) {
      _cooldownFrames = _repCooldownFrames;
      lastFailureReason = '';
      _topShoulderY = shoulderY;
    }
  }

  @override
  Map<String, double> get debugValues => {
    ...super.debugValues,
    'elbowAngle': _lastElbowAngle,
    'shoulderDrop': _lastShoulderDrop,
    'symmetryError': _lastSymmetryError,
    'cooldownFrames': _cooldownFrames.toDouble(),
  };

  bool _isSafeFraming(NuvoPoseFrame frame) {
    final points = criticalPoints
        .map(frame.point)
        .whereType<NuvoPosePoint>()
        .toList(growable: false);
    if (points.length != criticalPoints.length) return false;

    final minX = points.map((point) => point.x).reduce(math.min);
    final maxX = points.map((point) => point.x).reduce(math.max);
    final minY = points.map((point) => point.y).reduce(math.min);
    final maxY = points.map((point) => point.y).reduce(math.max);

    // A close/cropped camera view often produces a high-confidence pose, but
    // the extremities are clipped. Reject that geometry before phase matching.
    const edgeMargin = 0.04;
    const maximumSpan = 0.88;
    return minX >= edgeMargin &&
        maxX <= 1 - edgeMargin &&
        minY >= edgeMargin &&
        maxY <= 1 - edgeMargin &&
        maxX - minX <= maximumSpan &&
        maxY - minY <= maximumSpan;
  }
}

class JumpingJacksValidator extends _BaseValidator {
  JumpingJacksValidator({required super.targetValue});

  final RepCounterStateMachine _counter = RepCounterStateMachine();

  @override
  AiMotionActivity get activity => AiMotionActivity.jumpingJacks;
  @override
  int get currentValue => math.min(_counter.count, targetValue);
  @override
  String get statusText => 'Tracking motion';
  @override
  String get coachingText =>
      fullBodyVisible ? 'Keep moving' : 'Full body needed';
  @override
  List<String> get criticalPoints => const [
    'leftWrist',
    'rightWrist',
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftAnkle',
    'rightAnkle',
  ];

  @override
  void resetState() {
    _counter.reset();
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    _counter.update(_measureState(frame));
  }

  MovementPhase _measureState(NuvoPoseFrame frame) {
    final features = PoseFeatureExtractor(frame);
    final anklesWide = features.ankleWidth > features.bodyWidth * 1.38;
    final anklesClose = features.ankleWidth < features.bodyWidth * 1.18;
    if (features.wristsAboveShoulders && anklesWide) {
      return MovementPhase.active;
    }
    if (features.wristsNearBody && anklesClose) return MovementPhase.start;
    return MovementPhase.unknown;
  }
}

class ArmRaisesValidator extends _BaseValidator {
  ArmRaisesValidator({required super.targetValue});

  _OpenClosedState _stableState = _OpenClosedState.unknown;
  _OpenClosedState _candidateState = _OpenClosedState.unknown;
  int _candidateFrames = 0;
  bool _raised = false;
  int _reps = 0;
  double _lastWristRise = 0;

  // A transition is only accepted after this many consecutive frames agree —
  // a single noisy MLKit frame at the top or bottom can't flip the phase or
  // add a rep. Mirrors PushupsValidator._phaseStableFrames.
  static const _phaseStableFrames = 2;

  @override
  AiMotionActivity get activity => AiMotionActivity.armRaises;
  @override
  int get currentValue => math.min(_reps, targetValue);
  @override
  String get statusText => 'Tracking arm raises';
  @override
  String get coachingText =>
      fullBodyVisible ? 'Raise both arms cleanly' : 'Upper body needed';
  @override
  List<String> get criticalPoints => const [
    'leftWrist',
    'rightWrist',
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
  ];

  @override
  void resetState() {
    _stableState = _OpenClosedState.unknown;
    _candidateState = _OpenClosedState.unknown;
    _candidateFrames = 0;
    _raised = false;
    _reps = 0;
    _lastWristRise = 0;
  }

  @override
  Map<String, double> get debugValues => {
    ...super.debugValues,
    'stableState': _stableState.index.toDouble(),
    'raised': _raised ? 1 : 0,
    'wristRise': _lastWristRise,
    'count': _reps.toDouble(),
  };

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final leftWrist = frame.point('leftWrist')!;
    final rightWrist = frame.point('rightWrist')!;
    final leftShoulder = frame.point('leftShoulder')!;
    final rightShoulder = frame.point('rightShoulder')!;
    final leftHip = frame.point('leftHip')!;
    final rightHip = frame.point('rightHip')!;
    final shoulderY = (leftShoulder.y + rightShoulder.y) / 2;
    final hipY = (leftHip.y + rightHip.y) / 2;
    // Body-scale-relative so the same raise reads consistently at any camera
    // distance. torsoHeight is the shoulder→hip span; multipliers preserve the
    // previous effective offsets (~0.04 / ~0.03 / ~0.16) for a standard torso.
    final torsoHeight = (hipY - shoulderY).abs().clamp(0.12, 0.6);
    final up = leftWrist.y < shoulderY - torsoHeight * 0.16 &&
        rightWrist.y < shoulderY - torsoHeight * 0.16;
    final down = leftWrist.y > shoulderY + torsoHeight * 0.12 &&
        rightWrist.y > shoulderY + torsoHeight * 0.12 &&
        leftWrist.y < hipY + torsoHeight * 0.64;
    _lastWristRise = shoulderY - (leftWrist.y + rightWrist.y) / 2;
    final state = up
        ? _OpenClosedState.open
        : down
        ? _OpenClosedState.closed
        : _OpenClosedState.unknown;
    if (state == _OpenClosedState.unknown || state == _stableState) {
      _candidateState = _stableState;
      _candidateFrames = 0;
      return;
    }
    // Require _phaseStableFrames consecutive frames in the new state before
    // accepting the transition (jitter tolerance at the top and bottom).
    if (state == _candidateState) {
      _candidateFrames++;
    } else {
      _candidateState = state;
      _candidateFrames = 1;
    }
    if (_candidateFrames < _phaseStableFrames) return;

    _stableState = state;
    if (state == _OpenClosedState.open) _raised = true;
    if (state == _OpenClosedState.closed && _raised) {
      _reps++;
      _raised = false;
    }
  }
}

class SquatsValidator extends _BaseValidator {
  SquatsValidator({required super.targetValue});

  final RepCounterStateMachine _counter = RepCounterStateMachine();

  @override
  AiMotionActivity get activity => AiMotionActivity.squats;
  @override
  int get currentValue => math.min(_counter.count, targetValue);
  @override
  String get statusText => 'Tracking squats';
  @override
  String get coachingText =>
      fullBodyVisible ? 'Stand tall after each squat' : 'Full body needed';
  @override
  List<String> get criticalPoints => const [
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ];

  @override
  void resetState() {
    _counter.reset();
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final hipToKnee = PoseFeatureExtractor(frame).hipToKneeRatio();
    // Kept in lockstep with squatRepDefinition (see its comment for why the
    // thresholds moved from 0.86/0.58 to 0.72/0.50).
    final state = hipToKnee < 0.50
        ? MovementPhase.active
        : hipToKnee > 0.72
        ? MovementPhase.start
        : MovementPhase.unknown;
    _counter.update(state);
  }
}

class LungesValidator extends _BaseValidator {
  LungesValidator({required super.targetValue});

  final RepCounterStateMachine _counter = RepCounterStateMachine();

  @override
  AiMotionActivity get activity => AiMotionActivity.lunges;
  @override
  int get currentValue => math.min(_counter.count, targetValue);
  @override
  String get statusText => 'Tracking lunges';
  @override
  String get coachingText =>
      fullBodyVisible ? 'Drop into depth, then stand tall' : 'Full body needed';
  @override
  List<String> get criticalPoints => const [
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ];

  @override
  void resetState() {
    _counter.reset();
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final features = PoseFeatureExtractor(frame);
    final leftKneeAngle = features.kneeAngle(left: true);
    final rightKneeAngle = features.kneeAngle(left: false);
    final leftKneeBent = leftKneeAngle < 118;
    final rightKneeBent = rightKneeAngle < 118;
    final kneesSeparated =
        (frame.point('leftKnee')!.x - frame.point('rightKnee')!.x).abs() >
        features.hipWidth * 0.55;
    final bothStanding = leftKneeAngle > 154 && rightKneeAngle > 154;

    if (bothStanding) {
      _counter.update(MovementPhase.start);
      return;
    }
    if (kneesSeparated && (leftKneeBent || rightKneeBent)) {
      _counter.update(MovementPhase.active);
      return;
    }
    _counter.update(MovementPhase.unknown);
  }
}

class HighKneesValidator extends _BaseValidator {
  HighKneesValidator({required super.targetValue});

  bool _leftReady = true;
  bool _rightReady = true;
  int _count = 0;
  // Consecutive frames each knee has read as "raised". A rep only counts once
  // the knee has held above the line for _raiseStableFrames — a single noisy
  // frame that clips the threshold can't add a count.
  int _leftRaisedFrames = 0;
  int _rightRaisedFrames = 0;
  double _prevLeftKneeY = 1;
  double _prevRightKneeY = 1;
  double _lastLeftLift = 0;
  double _lastRightLift = 0;
  int _lastLeftDir = 0;

  static const _raiseStableFrames = 2;

  @override
  AiMotionActivity get activity => AiMotionActivity.highKnees;
  @override
  int get currentValue => math.min(_count, targetValue);
  @override
  String get statusText => 'Tracking high knees';
  @override
  String get coachingText =>
      fullBodyVisible ? 'Alternate knees above hip height' : 'Full body needed';
  @override
  List<String> get criticalPoints => const [
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
  ];

  @override
  void resetState() {
    _leftReady = true;
    _rightReady = true;
    _count = 0;
    _leftRaisedFrames = 0;
    _rightRaisedFrames = 0;
    _prevLeftKneeY = 1;
    _prevRightKneeY = 1;
    _lastLeftLift = 0;
    _lastRightLift = 0;
    _lastLeftDir = 0;
  }

  @override
  Map<String, double> get debugValues => {
    ...super.debugValues,
    'leftLift': _lastLeftLift,
    'rightLift': _lastRightLift,
    'leftDir': _lastLeftDir.toDouble(),
    'leftReady': _leftReady ? 1 : 0,
    'rightReady': _rightReady ? 1 : 0,
    'count': _count.toDouble(),
  };

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final leftHip = frame.point('leftHip')!;
    final rightHip = frame.point('rightHip')!;
    final leftKnee = frame.point('leftKnee')!;
    final rightKnee = frame.point('rightKnee')!;
    // Body-scale-relative thresholds so a knee lift reads the same whether the
    // person is close to or far from the camera. hipWidth is stable in every
    // frame (unlike hip-to-knee, which changes as the knee lifts). The
    // multipliers keep the effective values (~0.02 / ~0.12) unchanged for a
    // standard ~0.18 hip width.
    final hipWidth = ((leftHip.x - rightHip.x).abs()).clamp(0.06, 0.5);
    final raiseGap = hipWidth * 0.11;
    final lowerGap = hipWidth * 0.67;
    _lastLeftLift = leftHip.y - leftKnee.y;
    _lastRightLift = rightHip.y - rightKnee.y;
    final leftRaised = leftKnee.y < leftHip.y + raiseGap;
    final rightRaised = rightKnee.y < rightHip.y + raiseGap;
    final leftLowered = leftKnee.y > leftHip.y + lowerGap;
    final rightLowered = rightKnee.y > rightHip.y + lowerGap;
    // Direction, diagnostic only.
    final avgKneeY = (leftKnee.y + rightKnee.y) / 2;
    final prevAvg = (_prevLeftKneeY + _prevRightKneeY) / 2;
    _lastLeftDir = avgKneeY < prevAvg - 0.004
        ? -1
        : (avgKneeY > prevAvg + 0.004 ? 1 : 0);
    _prevLeftKneeY = leftKnee.y;
    _prevRightKneeY = rightKnee.y;

    if (leftLowered) _leftReady = true;
    if (rightLowered) _rightReady = true;

    // A knee that only jitters across the raise line never stacks two
    // consecutive "raised" frames, so _raiseStableFrames alone rejects it —
    // no separate direction gate needed for correctness.
    _leftRaisedFrames = leftRaised ? _leftRaisedFrames + 1 : 0;
    _rightRaisedFrames = rightRaised ? _rightRaisedFrames + 1 : 0;

    if (_leftReady && _leftRaisedFrames >= _raiseStableFrames) {
      _count++;
      _leftReady = false;
    }
    if (_rightReady && _rightRaisedFrames >= _raiseStableFrames) {
      _count++;
      _rightReady = false;
    }
  }
}

class PlankHoldValidator extends _BaseValidator {
  PlankHoldValidator({required super.targetValue});

  final HoldTimerStateMachine _timer = HoldTimerStateMachine();
  int _stableAlignmentFrames = 0;
  String _plankFeedback = 'Position your full body in frame.';
  double _hipLineError = 0;
  double _kneeLineError = 0;
  double _averageKneeAngle = 0;

  @override
  AiMotionActivity get activity => AiMotionActivity.plankHold;
  @override
  int get currentValue => math.min(_timer.seconds, targetValue);
  @override
  String get statusText => 'Tracking plank';
  @override
  String get coachingText => _plankFeedback;
  @override
  String get stateLabel =>
      _stableAlignmentFrames >= 4 ? 'hold_valid' : 'hold_paused';
  @override
  List<String> get criticalPoints => const [
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ];

  @override
  void resetState() {
    _timer.reset();
    _stableAlignmentFrames = 0;
    _plankFeedback = 'Position your full body in frame.';
    _hipLineError = 0;
    _kneeLineError = 0;
    _averageKneeAngle = 0;
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final features = PoseFeatureExtractor(frame);
    final shoulder = _mid(
      frame.point('leftShoulder')!,
      frame.point('rightShoulder')!,
    );
    final hip = _mid(frame.point('leftHip')!, frame.point('rightHip')!);
    final knee = _mid(frame.point('leftKnee')!, frame.point('rightKnee')!);
    final ankle = _mid(frame.point('leftAnkle')!, frame.point('rightAnkle')!);
    final bodyLength = _distance(shoulder, ankle).clamp(0.18, 1.2);
    _hipLineError = _distanceFromLine(hip, shoulder, ankle) / bodyLength;
    _kneeLineError = _distanceFromLine(knee, hip, ankle) / bodyLength;
    _averageKneeAngle =
        (features.kneeAngle(left: true) + features.kneeAngle(left: false)) / 2;

    final kneesBent = _averageKneeAngle < 148;
    final kneesDropped = knee.y > hip.y && _kneeLineError > 0.16;
    final hipsOutOfLine = _hipLineError > 0.16;
    final legsNotExtended = _kneeLineError > 0.18 || kneesBent;

    if (!fullBodyVisible) {
      _pause(
        frame,
        'low_landmark_confidence',
        'Position your full body in frame.',
      );
      return;
    }
    if (kneesDropped) {
      _pause(frame, 'knees_down', 'Lift your knees.');
      return;
    }
    if (legsNotExtended) {
      _pause(frame, 'legs_not_extended', 'Straighten your legs.');
      return;
    }
    if (hipsOutOfLine) {
      _pause(frame, 'body_line_broken', 'Keep your body in one line.');
      return;
    }

    _stableAlignmentFrames++;
    _plankFeedback = _stableAlignmentFrames >= 4
        ? 'Hold steady.'
        : 'Hold steady.';
    lastFailureReason = '';
    _timer.update(now: frame.createdAt, valid: _stableAlignmentFrames >= 4);
  }

  @override
  Map<String, double> get debugValues => {
    ...super.debugValues,
    'stableAlignmentFrames': _stableAlignmentFrames.toDouble(),
    'hipLineError': _hipLineError,
    'kneeLineError': _kneeLineError,
    'averageKneeAngle': _averageKneeAngle,
  };

  void _pause(NuvoPoseFrame frame, String reason, String feedback) {
    _stableAlignmentFrames = 0;
    lastFailureReason = reason;
    _plankFeedback = feedback;
    _timer.update(now: frame.createdAt, valid: false);
  }

  _Point _mid(NuvoPosePoint a, NuvoPosePoint b) =>
      _Point((a.x + b.x) / 2, (a.y + b.y) / 2);

  double _distance(_Point a, _Point b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _distanceFromLine(_Point point, _Point a, _Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 0.001) return _distance(point, a);
    return ((dy * point.x) - (dx * point.y) + (b.x * a.y) - (b.y * a.x)).abs() /
        length;
  }
}

class _Point {
  const _Point(this.x, this.y);

  final double x;
  final double y;
}

// ─────────────────────────────────────────────────────────────────────────────
// Configurable rep-counting validator engine
//
// A small, declarative system for expressing rep-based movement validators
// (squats, jumping jacks, lunges) as data instead of hand-written classes.
// Each definition specifies the START and ACTIVE conditions as a tree of
// pose-signal comparisons. ConfigurableRepValidator evaluates the tree,
// feeds the result into the existing RepCounterStateMachine, and inherits
// all frame-counting / confidence / finish behavior from _BaseValidator.
//
// Only the three movements whose conditions fit this model are routed here.
// Pushups, HighKnees, ArmRaises, and PlankHold keep their custom validators.
// ─────────────────────────────────────────────────────────────────────────────

/// Numeric signals extractable from a pose frame via [PoseFeatureExtractor].
/// Only the signals needed by the three configurable validators are listed.
enum PoseSignal {
  hipToKneeRatio,
  ankleWidthToBodyWidth,
  kneeSeparationToHipWidth,
  leftKneeAngle,
  rightKneeAngle;

  double extract(PoseFeatureExtractor f) => switch (this) {
    PoseSignal.hipToKneeRatio => f.hipToKneeRatio(),
    PoseSignal.ankleWidthToBodyWidth => f.ankleWidth / f.bodyWidth,
    PoseSignal.kneeSeparationToHipWidth =>
      (f.frame.point('leftKnee')!.x - f.frame.point('rightKnee')!.x).abs() /
          f.hipWidth,
    PoseSignal.leftKneeAngle => f.kneeAngle(left: true),
    PoseSignal.rightKneeAngle => f.kneeAngle(left: false),
  };
}

/// Boolean signals from [PoseFeatureExtractor].
enum BooleanPoseSignal {
  wristsAboveShoulders,
  wristsNearBody;

  bool extract(PoseFeatureExtractor f) => switch (this) {
    BooleanPoseSignal.wristsAboveShoulders => f.wristsAboveShoulders,
    BooleanPoseSignal.wristsNearBody => f.wristsNearBody,
  };
}

/// A condition evaluated against pose features. Returns true or false.
abstract class PoseCondition {
  const PoseCondition();

  bool evaluate(PoseFeatureExtractor features);
}

/// Compares a numeric [PoseSignal] against a constant [threshold].
class ComparisonCondition extends PoseCondition {
  const ComparisonCondition(
    this.signal,
    this.threshold, {
    required this.greaterThan,
  });

  final PoseSignal signal;
  final double threshold;
  final bool greaterThan;

  @override
  bool evaluate(PoseFeatureExtractor f) {
    final value = signal.extract(f);
    return greaterThan ? value > threshold : value < threshold;
  }
}

/// Wraps a [BooleanPoseSignal] as a condition.
class BooleanCondition extends PoseCondition {
  const BooleanCondition(this.signal);

  final BooleanPoseSignal signal;

  @override
  bool evaluate(PoseFeatureExtractor f) => signal.extract(f);
}

/// Logical AND of multiple conditions.
class AndCondition extends PoseCondition {
  const AndCondition(this.conditions);

  final List<PoseCondition> conditions;

  @override
  bool evaluate(PoseFeatureExtractor f) =>
      conditions.every((c) => c.evaluate(f));
}

/// Logical OR of multiple conditions.
class OrCondition extends PoseCondition {
  const OrCondition(this.conditions);

  final List<PoseCondition> conditions;

  @override
  bool evaluate(PoseFeatureExtractor f) => conditions.any((c) => c.evaluate(f));
}

/// Production validator that runs one or more [MultiPhaseSequenceTracker]s
/// in parallel and sums their completion counts.
///
/// This is the shared production runtime for [MovementFactoryFamily.multiPhaseSequence]
/// movements. Both Jump Squats and Lunge Jumps use this class — they differ
/// only in the [MultiPhaseSequenceDefinition]s passed in.
///
/// For single-direction movements (e.g., Jump Squats), one tracker runs.
/// For bidirectional movements (e.g., Lunge Jumps with both right-start
/// and left-start sequences), two trackers run in parallel on the same
/// frame stream. Only one tracker can progress at a time — when the user
/// is in a right lunge, the right-start tracker advances while the
/// left-start tracker sees a wrong-phase and resets to idle.
///
/// The [AirborneStateTracker] is owned by this validator and shared
/// across all trackers and definitions. It is updated once per frame
/// before any phase conditions are evaluated, ensuring air-detection
/// state is fresh and consistent.
class MultiPhaseSequenceValidator extends _BaseValidator {
  MultiPhaseSequenceValidator({
    required this.activity,
    required super.targetValue,
    required this.definitions,
    required this.statusText,
    required this.coachingTextActive,
    required this.coachingTextIncomplete,
  }) : _airborne = AirborneStateTracker() {
    final defs = definitions(_airborne);
    _trackers = defs
        .map((def) => MultiPhaseSequenceTracker(definition: def))
        .toList(growable: false);
  }

  @override
  final AiMotionActivity activity;

  /// Builds the sequence definition(s) given the runtime
  /// [AirborneStateTracker]. Called once in the constructor.
  final List<MultiPhaseSequenceDefinition> Function(
    AirborneStateTracker airborne,
  )
  definitions;

  final AirborneStateTracker _airborne;

  @override
  final String statusText;
  final String coachingTextActive;
  final String coachingTextIncomplete;

  late List<MultiPhaseSequenceTracker> _trackers;

  @override
  int get currentValue => math.min(_totalCompletions, targetValue);

  int get _totalCompletions =>
      _trackers.fold(0, (sum, t) => sum + t.completionCount);

  @override
  String get coachingText =>
      fullBodyVisible ? coachingTextActive : coachingTextIncomplete;

  @override
  List<String> get criticalPoints =>
      _trackers.first.definition.requiredLandmarks;

  @override
  void resetState() {
    for (final tracker in _trackers) {
      tracker.reset();
    }
    // Rebuild trackers to get fresh AirborneStateTracker state.
    _airborne.reset();
    final defs = definitions(_airborne);
    _trackers = defs
        .map((def) => MultiPhaseSequenceTracker(definition: def))
        .toList(growable: false);
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    // Update the shared AirborneStateTracker once per frame, then feed
    // the frame to each sequence tracker. The tracker reads
    // _airborne.isAirborne via AirborneCondition.
    _airborne.update(frame);
    for (final tracker in _trackers) {
      tracker.update(frame);
    }
  }

  /// Core landmarks that must be present for any phase evaluation.
  /// Ankles are excluded — they are frequently lost during airborne
  /// phases, and the AirborneStateTracker handles missing ankles
  /// gracefully. This override allows frames with missing ankles to
  /// still reach the tracker, improving real-world tolerance.
  static const _coreLandmarks = [
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
  ];

  @override
  MotionValidationUpdate update(NuvoPoseFrame frame) {
    framesAnalyzed++;

    // Always update the airborne tracker — it handles missing ankles
    // safely (returns early if landmarks are absent/low-likelihood).
    _airborne.update(frame);

    // Use relaxed landmark check: core landmarks (shoulders, hips, knees)
    // must be present, but ankles may be missing during airborne.
    if (!frame.hasPoints(_coreLandmarks)) {
      invalidPoseFrames++;
      lastVisibilityScore = 0;
      lastFailureReason = 'missing_landmarks';
      return snapshot();
    }
    validPoseFrames++;
    lastVisibilityScore = _visibilityScore(frame);
    if (!fullBodyVisible) {
      lastFailureReason = 'low_landmark_confidence';
    }

    // Feed frame to trackers. Each tracker checks its own
    // requiredLandmarks and skips if ankles are missing — but the
    // airborne tracker state is already fresh from the update above.
    for (final tracker in _trackers) {
      tracker.update(frame);
    }

    return snapshot();
  }
}

/// Verification-only definition for a rep-counting movement.
/// Contains no UI metadata (title, icon, animation) — that lives in the
/// movement catalog. This object only describes how to detect reps.
class RepMovementDefinition {
  const RepMovementDefinition({
    required this.activity,
    required this.requiredLandmarks,
    required this.startCondition,
    required this.activeCondition,
    required this.stableFrames,
    required this.statusText,
    required this.coachingTextActive,
    required this.coachingTextIncomplete,
  });

  final AiMotionActivity activity;
  final List<String> requiredLandmarks;
  final PoseCondition startCondition;
  final PoseCondition activeCondition;
  final int stableFrames;
  final String statusText;
  final String coachingTextActive;
  final String coachingTextIncomplete;

  String coachingText(bool fullBodyVisible) =>
      fullBodyVisible ? coachingTextActive : coachingTextIncomplete;
}

/// Generic rep-counting validator driven by a [RepMovementDefinition].
/// Extends [_BaseValidator] for frame-counting, visibility, confidence,
/// and finish behavior. Uses [RepCounterStateMachine] for counting —
/// no new counting algorithm.
class ConfigurableRepValidator extends _BaseValidator {
  ConfigurableRepValidator({
    required this.definition,
    required super.targetValue,
  });

  final RepMovementDefinition definition;
  final RepCounterStateMachine _counter = RepCounterStateMachine();
  MovementPhase _lastPhase = MovementPhase.unknown;
  double _lastHipToKneeRatio = 0;
  double _lastAnkleWidthToBodyWidth = 0;
  double _lastLeftKneeAngle = 180;
  double _lastRightKneeAngle = 180;
  double _lastKneeSeparation = 0;
  // -1 descending / deepening, +1 returning to start, 0 flat. Diagnostic only —
  // never gates counting (RepCounterStateMachine owns the sequencing).
  int _lastDirection = 0;
  double _prevDepthSignal = 0;
  int _repCountAtLastFrame = 0;

  @override
  AiMotionActivity get activity => definition.activity;

  @override
  int get currentValue => math.min(_counter.count, targetValue);

  @override
  String get statusText => definition.statusText;

  @override
  String get coachingText => definition.coachingText(fullBodyVisible);

  // stateLabel is inherited from _BaseValidator ('tracking') to preserve
  // parity with the original SquatsValidator/JumpingJacksValidator/
  // LungesValidator. The phase is still observable via debugValues['phase'].

  @override
  List<String> get criticalPoints => definition.requiredLandmarks;

  @override
  void resetState() {
    _counter.reset();
    _lastPhase = MovementPhase.unknown;
    _lastHipToKneeRatio = 0;
    _lastAnkleWidthToBodyWidth = 0;
    _lastLeftKneeAngle = 180;
    _lastRightKneeAngle = 180;
    _lastKneeSeparation = 0;
    _lastDirection = 0;
    _prevDepthSignal = 0;
    _repCountAtLastFrame = 0;
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final features = PoseFeatureExtractor(frame);
    // Diagnostic values — guarded so movements whose criticalPoints don't
    // include knees (e.g. jumping jacks) don't crash when knees are absent.
    // These never influence the counting logic below.
    if (frame.hasPoints(const [
      'leftKnee',
      'rightKnee',
      'leftHip',
      'rightHip',
      'leftShoulder',
      'rightShoulder',
    ])) {
      _lastHipToKneeRatio = features.hipToKneeRatio();
    }
    if (frame.hasPoints(const [
      'leftAnkle',
      'rightAnkle',
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
    ])) {
      _lastAnkleWidthToBodyWidth = features.ankleWidth / features.bodyWidth;
    }
    if (frame.hasPoints(const [
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ])) {
      _lastLeftKneeAngle = features.kneeAngle(left: true);
      _lastRightKneeAngle = features.kneeAngle(left: false);
      _lastKneeSeparation =
          (frame.point('leftKnee')!.x - frame.point('rightKnee')!.x).abs() /
              features.hipWidth;
      // Direction of the descent signal (lower hipToKneeRatio = deeper).
      // Small deadband so pose jitter reads as "flat", not oscillating.
      final delta = _lastHipToKneeRatio - _prevDepthSignal;
      _lastDirection = delta < -0.015 ? -1 : (delta > 0.015 ? 1 : 0);
      _prevDepthSignal = _lastHipToKneeRatio;
    }
    final phase = _measureState(features);
    _lastPhase = phase;
    _counter.update(phase, stableFrames: definition.stableFrames);
    _repCountAtLastFrame = _counter.count;
  }

  @override
  Map<String, double> get debugValues => {
    ...super.debugValues,
    'hipToKneeRatio': _lastHipToKneeRatio,
    'ankleWidthToBodyWidth': _lastAnkleWidthToBodyWidth,
    'leftKneeAngle': _lastLeftKneeAngle,
    'rightKneeAngle': _lastRightKneeAngle,
    'kneeSeparation': _lastKneeSeparation,
    'direction': _lastDirection.toDouble(),
    'phase': _lastPhase.index.toDouble(),
    'count': _repCountAtLastFrame.toDouble(),
  };

  MovementPhase _measureState(PoseFeatureExtractor features) {
    // Active is checked first, then start — matching the evaluation order
    // of SquatsValidator and JumpingJacksValidator. For LungesValidator the
    // original code checks start first, but the start and active conditions
    // are mutually exclusive (both knees > 154° implies neither < 118°), so
    // the order does not affect behavior.
    if (definition.activeCondition.evaluate(features)) {
      return MovementPhase.active;
    }
    if (definition.startCondition.evaluate(features)) {
      return MovementPhase.start;
    }
    return MovementPhase.unknown;
  }
}

// ── Movement definitions ─────────────────────────────────────────────────────

/// Squats: START when hips are high relative to knees (standing), ACTIVE when
/// deep. This feeds [RepCounterStateMachine], which already provides the full
/// temporal sequence: STANDING(start) -> DESCENDING(dead zone) -> DEPTH(active,
/// latches _hitActive) -> ASCENDING(dead zone) -> STANDING(count +1, re-arm).
/// 3 stable frames per transition suppress MLKit jitter; the count only fires
/// on the return to a clearly-standing pose, so holding the bottom, shallow
/// bends, jitter around a single threshold, and starting already-crouched all
/// score 0.
///
/// hipToKneeRatio = (kneeY - hipY) / torsoHeight. On device a normally-
/// proportioned person STANDING reads ~0.72-0.95 (torsoHeight is a large
/// fraction of the frame), not the ~1.1 the old synthetic fixtures assumed —
/// so the old start gate of 0.86 was frequently unreachable and no rep ever
/// counted. 0.72 / 0.50 keeps a ~0.22 dead band for hysteresis while making
/// the standing pose actually register.
const squatRepDefinition = RepMovementDefinition(
  activity: AiMotionActivity.squats,
  requiredLandmarks: [
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ],
  startCondition: ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.72,
    greaterThan: true,
  ),
  activeCondition: ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.50,
    greaterThan: false,
  ),
  stableFrames: 3,
  statusText: 'Tracking squats',
  coachingTextActive: 'Stand tall after each squat',
  coachingTextIncomplete: 'Full body needed',
);

/// Jumping Jacks: START when arms down + feet together, ACTIVE when arms up + feet wide.
const jumpingJackRepDefinition = RepMovementDefinition(
  activity: AiMotionActivity.jumpingJacks,
  requiredLandmarks: [
    'leftWrist',
    'rightWrist',
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftAnkle',
    'rightAnkle',
  ],
  startCondition: AndCondition([
    BooleanCondition(BooleanPoseSignal.wristsNearBody),
    ComparisonCondition(
      PoseSignal.ankleWidthToBodyWidth,
      1.18,
      greaterThan: false,
    ),
  ]),
  activeCondition: AndCondition([
    BooleanCondition(BooleanPoseSignal.wristsAboveShoulders),
    ComparisonCondition(
      PoseSignal.ankleWidthToBodyWidth,
      1.38,
      greaterThan: true,
    ),
  ]),
  stableFrames: 3,
  statusText: 'Tracking motion',
  coachingTextActive: 'Keep moving',
  coachingTextIncomplete: 'Full body needed',
);

/// Lunges: START when both legs straight, ACTIVE when knees separated + one bent.
const lungeRepDefinition = RepMovementDefinition(
  activity: AiMotionActivity.lunges,
  requiredLandmarks: [
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ],
  startCondition: AndCondition([
    ComparisonCondition(PoseSignal.leftKneeAngle, 154, greaterThan: true),
    ComparisonCondition(PoseSignal.rightKneeAngle, 154, greaterThan: true),
  ]),
  activeCondition: AndCondition([
    ComparisonCondition(
      PoseSignal.kneeSeparationToHipWidth,
      0.55,
      greaterThan: true,
    ),
    OrCondition([
      ComparisonCondition(PoseSignal.leftKneeAngle, 118, greaterThan: false),
      ComparisonCondition(PoseSignal.rightKneeAngle, 118, greaterThan: false),
    ]),
  ]),
  stableFrames: 3,
  statusText: 'Tracking lunges',
  coachingTextActive: 'Drop into depth, then stand tall',
  coachingTextIncomplete: 'Full body needed',
);

/// Sumo Squats: START when standing tall with wide stance, ACTIVE when deep
/// squat with wide stance. The wide stance (ankleWidthToBodyWidth > 1.5)
/// is the identity differentiator from regular squats (which have
/// ankleWidthToBodyWidth ~0.3-0.5). hipToKneeRatio captures the vertical
/// descent, same as standard squats.
const sumoSquatRepDefinition = RepMovementDefinition(
  activity: AiMotionActivity.sumoSquats,
  requiredLandmarks: [
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ],
  startCondition: AndCondition([
    ComparisonCondition(PoseSignal.hipToKneeRatio, 0.72, greaterThan: true),
    ComparisonCondition(
      PoseSignal.ankleWidthToBodyWidth,
      1.5,
      greaterThan: true,
    ),
  ]),
  activeCondition: AndCondition([
    ComparisonCondition(PoseSignal.hipToKneeRatio, 0.50, greaterThan: false),
    ComparisonCondition(
      PoseSignal.ankleWidthToBodyWidth,
      1.5,
      greaterThan: true,
    ),
  ]),
  stableFrames: 3,
  statusText: 'Tracking sumo squats',
  coachingTextActive: 'Stand tall after each squat',
  coachingTextIncomplete: 'Full body · wide stance needed',
);

/// Side Lunges: START when both legs straight, ACTIVE when one knee bent
/// with large lateral knee separation. The kneeSeparation > 0.85 threshold
/// is the identity differentiator from forward lunges (which produce
/// kneeSeparation ~0.55-0.70). Side lunges produce direct lateral
/// X-separation, while forward lunges produce Z-movement that only
/// partially shows as X-separation in 2D front view.
const sideLungeRepDefinition = RepMovementDefinition(
  activity: AiMotionActivity.sideLunges,
  requiredLandmarks: [
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ],
  startCondition: AndCondition([
    ComparisonCondition(PoseSignal.leftKneeAngle, 154, greaterThan: true),
    ComparisonCondition(PoseSignal.rightKneeAngle, 154, greaterThan: true),
  ]),
  activeCondition: AndCondition([
    ComparisonCondition(
      PoseSignal.kneeSeparationToHipWidth,
      0.85,
      greaterThan: true,
    ),
    OrCondition([
      ComparisonCondition(PoseSignal.leftKneeAngle, 118, greaterThan: false),
      ComparisonCondition(PoseSignal.rightKneeAngle, 118, greaterThan: false),
    ]),
  ]),
  stableFrames: 3,
  statusText: 'Tracking side lunges',
  coachingTextActive: 'Step out to the side, then stand tall',
  coachingTextIncomplete: 'Full body needed',
);

/// Deep Squats: START when standing tall, ACTIVE when hips drop well below
/// the standard squat depth. The hipToKneeRatio < 0.30 threshold is the
/// identity differentiator from regular squats (which use < 0.58).
///
/// hipToKneeRatio = (kneeY - hipY) / torsoHeight.
/// - Standing: ratio ~1.0+ (hips far above knees)
/// - Normal squat (thighs ~parallel): ratio ~0.40-0.55
/// - Deep squat (hips below knees): ratio ~0.10-0.25
///
/// The 0.30 threshold sits below the normal-squat range (~0.40-0.55) and
/// above the deep-squat range (~0.10-0.25), giving a categorical gap.
/// A normal valid squat (ratio 0.50) satisfies regular squats (< 0.58)
/// but does NOT satisfy deep squats (< 0.30). This is the identity proof.
const deepSquatRepDefinition = RepMovementDefinition(
  activity: AiMotionActivity.deepSquats,
  requiredLandmarks: [
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ],
  startCondition: ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.72,
    greaterThan: true,
  ),
  activeCondition: ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.30,
    greaterThan: false,
  ),
  stableFrames: 3,
  statusText: 'Tracking deep squats',
  coachingTextActive: 'Stand tall after each deep squat',
  coachingTextIncomplete: 'Full body · go below parallel',
);

/// Squat Jacks: START when closed (arms down, feet together, standing),
/// ACTIVE when open+squat (arms up, feet wide, AND squat depth).
///
/// This is a compound of three categorical signals:
/// - wristsAboveShoulders (arms up) — same as jumping jacks
/// - ankleWidthToBodyWidth > 1.18 (feet wide) — same as jumping jacks
/// - hipToKneeRatio < 0.58 (squat depth) — same as regular squats
///
/// Identity proof:
/// - vs Jumping Jacks: jumping jacks stay standing (hipToKneeRatio ~1.0),
///   so they fail the squat-depth condition. A squat jack race cannot be
///   cheated by doing jumping jacks.
/// - vs Squats: regular squats have arms down and feet together, so they
///   fail both the arms-up and feet-wide conditions. A squat jack race
///   cannot be cheated by doing regular squats.
/// - vs Deep Squats: deep squats have arms down and feet together, so
///   they fail the arms-up and feet-wide conditions.
///
/// The conjunction of three signals — none of which is unique alone —
/// creates a categorical identity that no single existing movement
/// satisfies.
const squatJackRepDefinition = RepMovementDefinition(
  activity: AiMotionActivity.squatJacks,
  requiredLandmarks: [
    'leftWrist',
    'rightWrist',
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftKnee',
    'rightKnee',
    'leftAnkle',
    'rightAnkle',
  ],
  startCondition: AndCondition([
    BooleanCondition(BooleanPoseSignal.wristsNearBody),
    ComparisonCondition(
      PoseSignal.ankleWidthToBodyWidth,
      1.18,
      greaterThan: false,
    ),
    ComparisonCondition(PoseSignal.hipToKneeRatio, 0.72, greaterThan: true),
  ]),
  activeCondition: AndCondition([
    BooleanCondition(BooleanPoseSignal.wristsAboveShoulders),
    ComparisonCondition(
      PoseSignal.ankleWidthToBodyWidth,
      1.38,
      greaterThan: true,
    ),
    ComparisonCondition(PoseSignal.hipToKneeRatio, 0.60, greaterThan: false),
  ]),
  stableFrames: 3,
  statusText: 'Tracking squat jacks',
  coachingTextActive: 'Jump wide, squat down, arms up — then return',
  coachingTextIncomplete: 'Full body · jump wide and squat',
);
