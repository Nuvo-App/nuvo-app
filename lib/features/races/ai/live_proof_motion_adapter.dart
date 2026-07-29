import 'live_proof_models.dart';
import 'motion_validators.dart';

class MotionLiveProofValidatorAdapter extends LiveProofValidator {
  MotionLiveProofValidatorAdapter({
    required LiveProofValidatorConfig config,
    required this._motionValidator,
  }) : super(config);

  final MotionValidator _motionValidator;

  @override
  int get currentValue => _motionValidator.currentValue;

  @override
  double get confidence => _motionValidator.confidence;

  @override
  int get framesAnalyzed => _motionValidator.framesAnalyzed;

  @override
  int get validSignalFrames => _motionValidator.validPoseFrames;

  @override
  int get durationMs => _motionValidator.durationMs;

  @override
  bool get primarySignalVisible => _motionValidator.fullBodyVisible;

  @override
  String get validatorState => _motionValidator.stateLabel;

  @override
  String get failedRuleReason => _motionValidator.failedRuleReason;

  @override
  void start() => _motionValidator.start();

  @override
  LiveProofUpdate update(LiveProofSignalBatch signals) {
    final poseSignal = signals.firstOfType<PoseLiveProofSignal>();
    if (poseSignal != null) {
      _motionValidator.update(poseSignal.frame);
    }
    return _toLiveProofUpdate();
  }

  @override
  LiveProofResult finish() {
    final result = _motionValidator.finish();
    return LiveProofResult(
      activityId: result.activity.backendValue,
      value: result.detectedReps,
      targetValue: result.targetReps,
      confidence: result.confidence,
      verificationStatus: result.verificationStatus,
      verificationSummary: result.verificationSummary,
      framesAnalyzed: result.framesAnalyzed,
      validSignalFrames: result.validPoseFrames,
      durationMs: result.durationMs,
      validatorVersion: result.validatorVersion,
    );
  }

  LiveProofUpdate _toLiveProofUpdate() {
    final targetComplete = currentValue >= targetValue;
    return LiveProofUpdate(
      activityId: activityId,
      currentValue: currentValue,
      targetValue: targetValue,
      confidence: confidence,
      status: targetComplete
          ? LiveProofStatus.targetComplete
          : LiveProofStatus.tracking,
      feedback: targetComplete
          ? 'Target complete.'
          : _motionValidator.fullBodyVisible
          ? _motionValidator.coachingText
          : 'Position your full body in frame.',
      framesAnalyzed: framesAnalyzed,
      validSignalFrames: validSignalFrames,
      durationMs: durationMs,
      primarySignalVisible: primarySignalVisible,
      debugValues: _motionValidator.debugValues,
      validatorState: validatorState,
      failedRuleReason: failedRuleReason,
    );
  }
}
