import 'dart:math' as math;

import '../data/ai_motion_models.dart';

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

MotionValidator createMotionValidator(
  AiMotionActivity activity,
  int targetValue,
) => switch (activity) {
  AiMotionActivity.jumpingJacks => JumpingJacksValidator(
    targetValue: targetValue,
  ),
  AiMotionActivity.squats => SquatsValidator(targetValue: targetValue),
  AiMotionActivity.highKnees => HighKneesValidator(targetValue: targetValue),
  AiMotionActivity.armRaises => ArmRaisesValidator(targetValue: targetValue),
  AiMotionActivity.plankHold => PlankHoldValidator(targetValue: targetValue),
  AiMotionActivity.pushUps => throw UnsupportedError(
    'Push-ups are not enabled for AI Motion Proof.',
  ),
};

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

  @override
  int get durationMs => startedAt == null
      ? 0
      : DateTime.now().difference(startedAt!).inMilliseconds;

  @override
  bool get fullBodyVisible => lastVisibilityScore >= 0.70;

  List<String> get criticalPoints;

  @override
  void start() {
    framesAnalyzed = 0;
    validPoseFrames = 0;
    invalidPoseFrames = 0;
    startedAt = DateTime.now();
    lastVisibilityScore = 0;
    resetState();
  }

  void resetState();

  @override
  MotionValidationUpdate update(NuvoPoseFrame frame) {
    framesAnalyzed++;
    if (!frame.hasPoints(criticalPoints)) {
      invalidPoseFrames++;
      lastVisibilityScore = 0;
      return snapshot();
    }
    validPoseFrames++;
    lastVisibilityScore = _visibilityScore(frame);
    analyzeValidFrame(frame);
    return snapshot();
  }

  void analyzeValidFrame(NuvoPoseFrame frame);

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

class JumpingJacksValidator extends _BaseValidator {
  JumpingJacksValidator({required super.targetValue});

  _OpenClosedState _stableState = _OpenClosedState.unknown;
  _OpenClosedState _candidateState = _OpenClosedState.unknown;
  int _candidateFrames = 0;
  bool _hasOpenedFromClosed = false;
  int _reps = 0;

  @override
  AiMotionActivity get activity => AiMotionActivity.jumpingJacks;
  @override
  int get currentValue => _reps;
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
    _stableState = _OpenClosedState.unknown;
    _candidateState = _OpenClosedState.unknown;
    _candidateFrames = 0;
    _hasOpenedFromClosed = false;
    _reps = 0;
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final measuredState = _measureState(frame);
    if (measuredState == _OpenClosedState.unknown) return;
    if (measuredState == _candidateState) {
      _candidateFrames++;
    } else {
      _candidateState = measuredState;
      _candidateFrames = 1;
    }
    if (_candidateFrames < 3 || measuredState == _stableState) return;
    final previousState = _stableState;
    _stableState = measuredState;
    if (previousState == _OpenClosedState.closed &&
        measuredState == _OpenClosedState.open) {
      _hasOpenedFromClosed = true;
      return;
    }
    if (previousState == _OpenClosedState.open &&
        measuredState == _OpenClosedState.closed &&
        _hasOpenedFromClosed) {
      _reps++;
      _hasOpenedFromClosed = false;
    }
  }

  _OpenClosedState _measureState(NuvoPoseFrame frame) {
    final leftWrist = frame.point('leftWrist')!;
    final rightWrist = frame.point('rightWrist')!;
    final leftShoulder = frame.point('leftShoulder')!;
    final rightShoulder = frame.point('rightShoulder')!;
    final leftHip = frame.point('leftHip')!;
    final rightHip = frame.point('rightHip')!;
    final leftAnkle = frame.point('leftAnkle')!;
    final rightAnkle = frame.point('rightAnkle')!;
    final shoulderY = (leftShoulder.y + rightShoulder.y) / 2;
    final hipY = (leftHip.y + rightHip.y) / 2;
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final hipWidth = (leftHip.x - rightHip.x).abs();
    final bodyWidth = math.max(shoulderWidth, hipWidth).clamp(0.08, 0.6);
    final ankleWidth = (leftAnkle.x - rightAnkle.x).abs();
    final wristsAboveShoulders =
        leftWrist.y < shoulderY - 0.03 && rightWrist.y < shoulderY - 0.03;
    final wristsDown =
        leftWrist.y > shoulderY - 0.01 &&
        rightWrist.y > shoulderY - 0.01 &&
        leftWrist.y < hipY + 0.24 &&
        rightWrist.y < hipY + 0.24;
    final anklesWide = ankleWidth > bodyWidth * 1.38;
    final anklesClose = ankleWidth < bodyWidth * 1.18;
    if (wristsAboveShoulders && anklesWide) return _OpenClosedState.open;
    if (wristsDown && anklesClose) return _OpenClosedState.closed;
    return _OpenClosedState.unknown;
  }
}

class ArmRaisesValidator extends _BaseValidator {
  ArmRaisesValidator({required super.targetValue});

  _OpenClosedState _stableState = _OpenClosedState.unknown;
  bool _raised = false;
  int _reps = 0;

  @override
  AiMotionActivity get activity => AiMotionActivity.armRaises;
  @override
  int get currentValue => _reps;
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
    _raised = false;
    _reps = 0;
  }

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
    final up =
        leftWrist.y < shoulderY - 0.04 && rightWrist.y < shoulderY - 0.04;
    final down =
        leftWrist.y > shoulderY + 0.03 &&
        rightWrist.y > shoulderY + 0.03 &&
        leftWrist.y < hipY + 0.16;
    final state = up
        ? _OpenClosedState.open
        : down
        ? _OpenClosedState.closed
        : _OpenClosedState.unknown;
    if (state == _OpenClosedState.unknown || state == _stableState) return;
    _stableState = state;
    if (state == _OpenClosedState.open) _raised = true;
    if (state == _OpenClosedState.closed && _raised) {
      _reps++;
      _raised = false;
    }
  }
}

enum _SquatState { unknown, standing, down }

class SquatsValidator extends _BaseValidator {
  SquatsValidator({required super.targetValue});

  _SquatState _stableState = _SquatState.unknown;
  bool _hitDepth = false;
  int _reps = 0;

  @override
  AiMotionActivity get activity => AiMotionActivity.squats;
  @override
  int get currentValue => _reps;
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
    _stableState = _SquatState.unknown;
    _hitDepth = false;
    _reps = 0;
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final leftHip = frame.point('leftHip')!;
    final rightHip = frame.point('rightHip')!;
    final leftKnee = frame.point('leftKnee')!;
    final rightKnee = frame.point('rightKnee')!;
    final leftShoulder = frame.point('leftShoulder')!;
    final rightShoulder = frame.point('rightShoulder')!;
    final hipY = (leftHip.y + rightHip.y) / 2;
    final kneeY = (leftKnee.y + rightKnee.y) / 2;
    final shoulderY = (leftShoulder.y + rightShoulder.y) / 2;
    final torso = (hipY - shoulderY).abs().clamp(0.12, 0.6);
    final hipToKnee = (kneeY - hipY) / torso;
    final state = hipToKnee < 0.58
        ? _SquatState.down
        : hipToKnee > 0.86
        ? _SquatState.standing
        : _SquatState.unknown;
    if (state == _SquatState.unknown || state == _stableState) return;
    _stableState = state;
    if (state == _SquatState.down) _hitDepth = true;
    if (state == _SquatState.standing && _hitDepth) {
      _reps++;
      _hitDepth = false;
    }
  }
}

class HighKneesValidator extends _BaseValidator {
  HighKneesValidator({required super.targetValue});

  bool _leftReady = true;
  bool _rightReady = true;
  int _count = 0;

  @override
  AiMotionActivity get activity => AiMotionActivity.highKnees;
  @override
  int get currentValue => _count;
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
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final leftHip = frame.point('leftHip')!;
    final rightHip = frame.point('rightHip')!;
    final leftKnee = frame.point('leftKnee')!;
    final rightKnee = frame.point('rightKnee')!;
    final leftRaised = leftKnee.y < leftHip.y + 0.02;
    final rightRaised = rightKnee.y < rightHip.y + 0.02;
    final leftLowered = leftKnee.y > leftHip.y + 0.12;
    final rightLowered = rightKnee.y > rightHip.y + 0.12;
    if (leftLowered) _leftReady = true;
    if (rightLowered) _rightReady = true;
    if (leftRaised && _leftReady) {
      _count++;
      _leftReady = false;
    }
    if (rightRaised && _rightReady) {
      _count++;
      _rightReady = false;
    }
  }
}

class PlankHoldValidator extends _BaseValidator {
  PlankHoldValidator({required super.targetValue});

  int _validHoldMs = 0;
  DateTime? _lastValidFrameAt;

  @override
  AiMotionActivity get activity => AiMotionActivity.plankHold;
  @override
  int get currentValue => (_validHoldMs / 1000).floor();
  @override
  String get statusText => 'Tracking plank';
  @override
  String get coachingText => fullBodyVisible
      ? 'Keep shoulder, hip, and ankle aligned'
      : 'Side view needed';
  @override
  List<String> get criticalPoints => const [
    'leftShoulder',
    'rightShoulder',
    'leftHip',
    'rightHip',
    'leftAnkle',
    'rightAnkle',
  ];

  @override
  void resetState() {
    _validHoldMs = 0;
    _lastValidFrameAt = null;
  }

  @override
  void analyzeValidFrame(NuvoPoseFrame frame) {
    final shoulder = _mid(
      frame.point('leftShoulder')!,
      frame.point('rightShoulder')!,
    );
    final hip = _mid(frame.point('leftHip')!, frame.point('rightHip')!);
    final ankle = _mid(frame.point('leftAnkle')!, frame.point('rightAnkle')!);
    final bodySpan = math.max((shoulder.x - ankle.x).abs(), 0.1);
    final hipLineY = _interpolateY(shoulder, ankle, hip.x);
    final straightEnough = (hip.y - hipLineY).abs() < bodySpan * 0.34;
    if (!straightEnough) {
      _lastValidFrameAt = null;
      return;
    }
    final now = frame.createdAt;
    if (_lastValidFrameAt != null) {
      final delta = now.difference(_lastValidFrameAt!).inMilliseconds;
      if (delta > 0 && delta < 500) _validHoldMs += delta;
    }
    _lastValidFrameAt = now;
  }

  _Point _mid(NuvoPosePoint a, NuvoPosePoint b) =>
      _Point((a.x + b.x) / 2, (a.y + b.y) / 2);

  double _interpolateY(_Point a, _Point b, double x) {
    final dx = b.x - a.x;
    if (dx.abs() < 0.001) return (a.y + b.y) / 2;
    final t = ((x - a.x) / dx).clamp(0.0, 1.0);
    return a.y + (b.y - a.y) * t;
  }
}

class _Point {
  const _Point(this.x, this.y);

  final double x;
  final double y;
}
