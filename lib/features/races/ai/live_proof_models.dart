import '../data/ai_motion_models.dart';
import '../domain/motion_activity.dart';

enum LiveProofSignalType { pose, object, scene, timer, cloudflareVision }

enum LiveProofStatus {
  setup,
  waitingForSignal,
  tracking,
  targetComplete,
  verified,
  failed,
}

class LiveProofActivityDefinition {
  const LiveProofActivityDefinition({
    required this.activityId,
    required this.title,
    required this.metric,
    required this.unit,
    required this.defaultTarget,
    required this.supportedFormats,
    required this.requiredSignals,
    required this.validatorVersion,
    required this.createValidator,
    this.instructions = const [],
    this.minimumConfidence = 0.65,
    this.isHold = false,
  });

  final String activityId;
  final String title;
  final RaceMetric metric;
  final String unit;
  final int defaultTarget;
  final List<RaceFormat> supportedFormats;
  final Set<LiveProofSignalType> requiredSignals;
  final String validatorVersion;
  final LiveProofValidatorFactory createValidator;
  final List<String> instructions;
  final double minimumConfidence;
  final bool isHold;
}

typedef LiveProofValidatorFactory =
    LiveProofValidator Function(LiveProofValidatorConfig config);

class LiveProofValidatorConfig {
  const LiveProofValidatorConfig({
    required this.activityId,
    required this.targetValue,
    required this.metric,
    required this.unit,
    required this.validatorVersion,
    this.minimumConfidence = 0.65,
    this.isHold = false,
  });

  final String activityId;
  final int targetValue;
  final RaceMetric metric;
  final String unit;
  final String validatorVersion;
  final double minimumConfidence;
  final bool isHold;
}

abstract class LiveProofSignal {
  const LiveProofSignal({required this.type, required this.createdAt});

  final LiveProofSignalType type;
  final DateTime createdAt;
}

class PoseLiveProofSignal extends LiveProofSignal {
  PoseLiveProofSignal({required this.frame})
    : super(type: LiveProofSignalType.pose, createdAt: frame.createdAt);

  final NuvoPoseFrame frame;
}

class TimerLiveProofSignal extends LiveProofSignal {
  TimerLiveProofSignal({required this.elapsed})
    : super(type: LiveProofSignalType.timer, createdAt: DateTime.now());

  final Duration elapsed;
}

class CloudflareVisionLiveProofSignal extends LiveProofSignal {
  CloudflareVisionLiveProofSignal({
    required this.observationId,
    required this.prompt,
    required this.activityDetected,
    required this.actionComplete,
    required this.confidence,
    required this.summary,
    DateTime? createdAt,
    this.metadata = const {},
  }) : super(
         type: LiveProofSignalType.cloudflareVision,
         createdAt: createdAt ?? DateTime.now(),
       );

  final String observationId;
  final String prompt;
  final bool activityDetected;
  final bool actionComplete;
  final double confidence;
  final String summary;
  final Map<String, Object?> metadata;
}

class LiveProofSignalBatch {
  const LiveProofSignalBatch({required this.signals});

  final List<LiveProofSignal> signals;

  T? firstOfType<T extends LiveProofSignal>() {
    for (final signal in signals) {
      if (signal is T) return signal;
    }
    return null;
  }
}

class LiveProofUpdate {
  const LiveProofUpdate({
    required this.activityId,
    required this.currentValue,
    required this.targetValue,
    required this.confidence,
    required this.status,
    required this.feedback,
    required this.framesAnalyzed,
    required this.validSignalFrames,
    required this.durationMs,
    required this.primarySignalVisible,
    this.debugValues = const {},
    this.validatorState = '',
    this.failedRuleReason = '',
  });

  final String activityId;
  final int currentValue;
  final int targetValue;
  final double confidence;
  final LiveProofStatus status;
  final String feedback;
  final int framesAnalyzed;
  final int validSignalFrames;
  final int durationMs;
  final bool primarySignalVisible;
  final Map<String, double> debugValues;
  final String validatorState;
  final String failedRuleReason;

  bool get targetComplete => currentValue >= targetValue;
}

class LiveProofResult {
  const LiveProofResult({
    required this.activityId,
    required this.value,
    required this.targetValue,
    required this.confidence,
    required this.verificationStatus,
    required this.verificationSummary,
    required this.framesAnalyzed,
    required this.validSignalFrames,
    required this.durationMs,
    required this.validatorVersion,
    this.metadata = const {},
  });

  final String activityId;
  final int value;
  final int targetValue;
  final double confidence;
  final String verificationStatus;
  final String verificationSummary;
  final int framesAnalyzed;
  final int validSignalFrames;
  final int durationMs;
  final String validatorVersion;
  final Map<String, Object?> metadata;

  bool get isVerified => verificationStatus == 'ai_verified';

  AiMotionResult toAiMotionResult() => AiMotionResult(
    activity: AiMotionActivity.fromBackendValue(activityId),
    targetReps: targetValue,
    detectedReps: value,
    confidence: confidence,
    verificationStatus: verificationStatus,
    verificationSummary: verificationSummary,
    framesAnalyzed: framesAnalyzed,
    validPoseFrames: validSignalFrames,
    durationMs: durationMs,
    validatorVersion: validatorVersion,
  );
}

abstract class LiveProofValidator {
  LiveProofValidator(this.config);

  final LiveProofValidatorConfig config;

  String get activityId => config.activityId;
  int get targetValue => config.targetValue;
  int get currentValue;
  double get confidence;
  int get framesAnalyzed;
  int get validSignalFrames;
  int get durationMs;
  bool get primarySignalVisible;
  String get validatorState;
  String get failedRuleReason;

  void start();
  LiveProofUpdate update(LiveProofSignalBatch signals);
  LiveProofResult finish();
  void reset() => start();
}
