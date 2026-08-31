import 'dart:math' as math;

import '../data/ai_motion_models.dart';

enum JumpingJackMotionState { unknown, closed, open }

class JumpingJackCounter {
  JumpingJackCounter({required this.targetReps, this.stableFramesRequired = 3});

  static const validatorVersion = 'nuvo-ai-motion-v1';

  final int targetReps;
  final int stableFramesRequired;

  int detectedReps = 0;
  int framesAnalyzed = 0;
  int validPoseFrames = 0;
  int invalidPoseFrames = 0;

  DateTime? _startedAt;
  JumpingJackMotionState _stableState = JumpingJackMotionState.unknown;
  JumpingJackMotionState _candidateState = JumpingJackMotionState.unknown;
  int _candidateFrames = 0;
  bool _hasOpenedFromClosed = false;
  double _lastVisibilityScore = 0;

  JumpingJackMotionState get currentState => _stableState;
  double get lastVisibilityScore => _lastVisibilityScore;
  bool get fullBodyVisible => _lastVisibilityScore >= 0.72;

  void start() {
    detectedReps = 0;
    framesAnalyzed = 0;
    validPoseFrames = 0;
    invalidPoseFrames = 0;
    _startedAt = DateTime.now();
    _stableState = JumpingJackMotionState.unknown;
    _candidateState = JumpingJackMotionState.unknown;
    _candidateFrames = 0;
    _hasOpenedFromClosed = false;
    _lastVisibilityScore = 0;
  }

  void analyze(NuvoPoseFrame? frame) {
    framesAnalyzed++;
    if (frame == null || !_hasCriticalPoints(frame)) {
      invalidPoseFrames++;
      _lastVisibilityScore = 0;
      return;
    }

    validPoseFrames++;
    _lastVisibilityScore = _visibilityScore(frame);

    final measuredState = _measureState(frame);
    if (measuredState == JumpingJackMotionState.unknown) {
      return;
    }

    if (measuredState == _candidateState) {
      _candidateFrames++;
    } else {
      _candidateState = measuredState;
      _candidateFrames = 1;
    }

    if (_candidateFrames < stableFramesRequired ||
        measuredState == _stableState) {
      return;
    }

    final previousState = _stableState;
    _stableState = measuredState;

    if (previousState == JumpingJackMotionState.closed &&
        measuredState == JumpingJackMotionState.open) {
      _hasOpenedFromClosed = true;
      return;
    }

    if (previousState == JumpingJackMotionState.open &&
        measuredState == JumpingJackMotionState.closed &&
        _hasOpenedFromClosed) {
      detectedReps++;
      _hasOpenedFromClosed = false;
    }
  }

  AiMotionResult finish() {
    final durationMs = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inMilliseconds;
    final verified = detectedReps >= targetReps && confidence >= 0.62;
    return AiMotionResult(
      activity: AiMotionActivity.jumpingJacks,
      targetReps: targetReps,
      detectedReps: detectedReps,
      confidence: confidence,
      verificationStatus: verified ? 'ai_verified' : 'ai_failed',
      verificationSummary: verified
          ? 'Detected $detectedReps jumping jacks from live pose tracking.'
          : 'Nuvo detected $detectedReps clean reps out of $targetReps.',
      framesAnalyzed: framesAnalyzed,
      validPoseFrames: validPoseFrames,
      durationMs: durationMs,
      validatorVersion: validatorVersion,
    );
  }

  double get confidence {
    if (framesAnalyzed == 0) return 0;
    final validRatio = validPoseFrames / framesAnalyzed;
    final targetRatio = math.min(1.0, detectedReps / targetReps);
    final invalidPenalty = math.min(0.25, invalidPoseFrames / framesAnalyzed);
    final stabilityBonus = _stableState == JumpingJackMotionState.unknown
        ? 0.0
        : 0.08;
    return (validRatio * 0.55 + targetRatio * 0.37 + stabilityBonus).clamp(
      0.0,
      1.0 - invalidPenalty,
    );
  }

  bool get hasEnoughFrames => framesAnalyzed >= 18 && validPoseFrames >= 8;

  bool _hasCriticalPoints(NuvoPoseFrame frame) =>
      frame.hasPoints(_criticalPoints);

  double _visibilityScore(NuvoPoseFrame frame) {
    var total = 0.0;
    for (final name in _criticalPoints) {
      total += frame.point(name)?.likelihood ?? 0;
    }
    return total / _criticalPoints.length;
  }

  JumpingJackMotionState _measureState(NuvoPoseFrame frame) {
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

    if (wristsAboveShoulders && anklesWide) {
      return JumpingJackMotionState.open;
    }
    if (wristsDown && anklesClose) {
      return JumpingJackMotionState.closed;
    }
    return JumpingJackMotionState.unknown;
  }
}

const _criticalPoints = [
  'leftWrist',
  'rightWrist',
  'leftShoulder',
  'rightShoulder',
  'leftHip',
  'rightHip',
  'leftAnkle',
  'rightAnkle',
];
