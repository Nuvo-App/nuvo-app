import '../domain/motion_activity.dart';
import 'local_motion_signature.dart';
import 'live_proof_models.dart';

const kUniversalLiveProofValidatorVersion = 'nuvo-universal-local-motion-v1';

LiveProofActivityDefinition universalLiveProofActivityDefinition({
  required String activityId,
  required String title,
  required RaceMetric metric,
  required String unit,
  required int defaultTarget,
  required String proofPrompt,
  List<RaceFormat> supportedFormats = const [
    RaceFormat.firstToGoal,
    RaceFormat.mostInWindow,
    RaceFormat.bestAttempt,
    RaceFormat.timedAttempt,
  ],
  List<String> instructions = const [
    'Keep the activity visible.',
    'Keep the phone steady.',
    'Wait for Nuvo to count clean progress.',
  ],
  double minimumConfidence = 0.72,
  LocalMotionSignature? motionSignature,
}) {
  return LiveProofActivityDefinition(
    activityId: activityId,
    title: title,
    metric: metric,
    unit: unit,
    defaultTarget: defaultTarget,
    supportedFormats: supportedFormats,
    requiredSignals: motionSignature == null
        ? const {LiveProofSignalType.cloudflareVision}
        : const {LiveProofSignalType.pose},
    validatorVersion: kUniversalLiveProofValidatorVersion,
    instructions: instructions,
    minimumConfidence: minimumConfidence,
    createValidator: (config) => UniversalLiveProofValidator(
      config: config,
      proofPrompt: proofPrompt,
      motionSignature: motionSignature,
    ),
  );
}

class UniversalLiveProofValidator extends LiveProofValidator {
  UniversalLiveProofValidator({
    required LiveProofValidatorConfig config,
    required this.proofPrompt,
    this.motionSignature,
  }) : super(config);

  final String proofPrompt;
  final LocalMotionSignature? motionSignature;
  final Set<String> _countedObservationIds = <String>{};
  final Map<String, double> _debugValues = <String, double>{};

  DateTime? _startedAt;
  int _currentValue = 0;
  int _framesAnalyzed = 0;
  int _validSignalFrames = 0;
  double _confidence = 0;
  bool _primarySignalVisible = false;
  bool _armedForNextCount = true;
  String _feedback = 'Show Nuvo the activity.';
  String _failedRuleReason = '';

  @override
  int get currentValue => _currentValue;

  @override
  double get confidence => _confidence;

  @override
  int get framesAnalyzed => _framesAnalyzed;

  @override
  int get validSignalFrames => _validSignalFrames;

  @override
  int get durationMs {
    final startedAt = _startedAt;
    if (startedAt == null) return 0;
    return DateTime.now().difference(startedAt).inMilliseconds;
  }

  @override
  bool get primarySignalVisible => _primarySignalVisible;

  @override
  String get validatorState => _currentValue >= targetValue
      ? 'target_complete'
      : _primarySignalVisible
      ? 'tracking'
      : 'waiting_for_activity';

  @override
  String get failedRuleReason => _failedRuleReason;

  @override
  void start() {
    _startedAt = DateTime.now();
    _currentValue = 0;
    _framesAnalyzed = 0;
    _validSignalFrames = 0;
    _confidence = 0;
    _primarySignalVisible = false;
    _armedForNextCount = true;
    _feedback = 'Show Nuvo the activity.';
    _failedRuleReason = '';
    _countedObservationIds.clear();
    _debugValues.clear();
  }

  @override
  LiveProofUpdate update(LiveProofSignalBatch signals) {
    final signature = motionSignature;
    final poseSignal = signals.firstOfType<PoseLiveProofSignal>();
    if (signature != null && poseSignal != null) {
      return _updatePose(signature, poseSignal);
    }

    final signal = signals.firstOfType<CloudflareVisionLiveProofSignal>();
    if (signal == null) return _update();

    _framesAnalyzed++;
    _confidence = signal.confidence.clamp(0, 1);
    _primarySignalVisible = signal.activityDetected;
    _debugValues['cloudflareConfidence'] = _confidence;
    _debugValues['activityDetected'] = signal.activityDetected ? 1 : 0;
    _debugValues['actionComplete'] = signal.actionComplete ? 1 : 0;

    if (!signal.activityDetected) {
      _failedRuleReason = 'activity_not_visible';
      _feedback = 'Bring the activity into frame.';
      return _update();
    }

    _validSignalFrames++;

    if (_confidence < config.minimumConfidence) {
      _failedRuleReason = 'low_confidence';
      _feedback = 'Hold the frame steady so Nuvo can read it.';
      return _update();
    }

    if (!signal.actionComplete) {
      _failedRuleReason = 'action_not_complete';
      _feedback = signal.summary.isEmpty ? 'Keep going.' : signal.summary;
      return _update();
    }

    _failedRuleReason = '';
    _feedback = signal.summary.isEmpty ? 'That counts.' : signal.summary;
    if (_countedObservationIds.add(signal.observationId)) {
      _currentValue++;
    }
    return _update();
  }

  LiveProofUpdate _updatePose(
    LocalMotionSignature signature,
    PoseLiveProofSignal signal,
  ) {
    _framesAnalyzed++;
    final match = signature.evaluate(signal.frame);
    _primarySignalVisible = match.visible;
    _confidence = match.confidence;
    _debugValues['motionProgress'] = match.progress;
    _debugValues['motionCompleteness'] = match.completeness;
    _debugValues['rejectSimilarity'] = match.rejectSimilarity;

    if (!match.visible) {
      _failedRuleReason = 'body_not_visible';
      _feedback = 'Step back so Nuvo can see the full motion.';
      return _update();
    }

    _validSignalFrames++;

    if (match.confidence < config.minimumConfidence * 0.72) {
      _failedRuleReason = 'low_pose_confidence';
      _feedback = 'Hold the phone steady. Nuvo is finding the motion.';
      return _update();
    }

    if (match.progress <= signature.resetProgress) {
      _armedForNextCount = true;
      _failedRuleReason = 'reset_ready';
      _feedback = 'Reset seen. Hit the next one.';
      return _update();
    }

    if (match.rejectSimilarity > 0.86 && match.progress < 0.72) {
      _failedRuleReason = 'matches_reject_example';
      _feedback = 'That looked like the reject example.';
      return _update();
    }

    if (_armedForNextCount && match.progress >= signature.minProgressToCount) {
      _currentValue++;
      _armedForNextCount = false;
      _failedRuleReason = '';
      _feedback = 'That counts.';
      return _update();
    }

    _failedRuleReason = 'motion_in_progress';
    _feedback = 'Keep going through the full motion.';
    return _update();
  }

  @override
  LiveProofResult finish() {
    final verified =
        _currentValue >= targetValue && _confidence >= config.minimumConfidence;
    return LiveProofResult(
      activityId: activityId,
      value: _currentValue,
      targetValue: targetValue,
      confidence: _confidence,
      verificationStatus: verified ? 'ai_verified' : 'ai_failed',
      verificationSummary: verified
          ? 'Nuvo verified $_currentValue ${config.unit}.'
          : 'Nuvo counted $_currentValue of $targetValue ${config.unit}.',
      framesAnalyzed: framesAnalyzed,
      validSignalFrames: validSignalFrames,
      durationMs: durationMs,
      validatorVersion: config.validatorVersion,
      metadata: {
        'proofPrompt': proofPrompt,
        'requiredSignal': motionSignature == null
            ? LiveProofSignalType.cloudflareVision.name
            : LiveProofSignalType.pose.name,
        if (motionSignature != null)
          'motionSignatureVersion': motionSignature!.version,
      },
    );
  }

  LiveProofUpdate _update() {
    final targetComplete = _currentValue >= targetValue;
    return LiveProofUpdate(
      activityId: activityId,
      currentValue: _currentValue,
      targetValue: targetValue,
      confidence: _confidence,
      status: targetComplete
          ? LiveProofStatus.targetComplete
          : LiveProofStatus.tracking,
      feedback: targetComplete ? 'Finish line ready.' : _feedback,
      framesAnalyzed: framesAnalyzed,
      validSignalFrames: validSignalFrames,
      durationMs: durationMs,
      primarySignalVisible: primarySignalVisible,
      debugValues: Map.unmodifiable(_debugValues),
      validatorState: validatorState,
      failedRuleReason: failedRuleReason,
    );
  }
}
