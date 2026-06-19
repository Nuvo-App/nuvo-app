enum AiMotionActivity {
  jumpingJacks,
  pushUps;

  String get backendValue => switch (this) {
    AiMotionActivity.jumpingJacks => 'jumping_jacks',
    AiMotionActivity.pushUps => 'push_ups',
  };

  String get label => switch (this) {
    AiMotionActivity.jumpingJacks => 'jumping jacks',
    AiMotionActivity.pushUps => 'push-ups',
  };
}

enum AiMotionProofStatus {
  setup,
  cameraReady,
  recording,
  processing,
  aiVerified,
  aiFailed,
  needsReview,
  submitting,
  submitted,
  permissionDenied,
  cameraError,
}

class AiMotionResult {
  const AiMotionResult({
    required this.activity,
    required this.targetReps,
    required this.detectedReps,
    required this.confidence,
    required this.verificationStatus,
    required this.verificationSummary,
    required this.framesAnalyzed,
    required this.validPoseFrames,
    required this.durationMs,
    required this.validatorVersion,
  });

  final AiMotionActivity activity;
  final int targetReps;
  final int detectedReps;
  final double confidence;
  final String verificationStatus;
  final String verificationSummary;
  final int framesAnalyzed;
  final int validPoseFrames;
  final int durationMs;
  final String validatorVersion;

  bool get isVerified => verificationStatus == 'ai_verified';

  Map<String, dynamic> toProofPayload() => {
    'proofType': 'ai_motion',
    'activityType': activity.backendValue,
    'note': 'AI motion proof: $detectedReps ${activity.label} detected.',
    'value': detectedReps,
    'targetValue': targetReps,
    'detectedValue': detectedReps,
    'confidence': confidence,
    'verificationStatus': verificationStatus,
    'verificationSummary': verificationSummary,
    'framesAnalyzed': framesAnalyzed,
    'validPoseFrames': validPoseFrames,
    'durationMs': durationMs,
    'validatorVersion': validatorVersion,
  };
}

class NuvoPoseFrame {
  const NuvoPoseFrame({
    required this.points,
    required this.imageWidth,
    required this.imageHeight,
    required this.createdAt,
  });

  final Map<String, NuvoPosePoint> points;
  final double imageWidth;
  final double imageHeight;
  final DateTime createdAt;

  NuvoPosePoint? point(String name) => points[name];

  bool hasPoints(Iterable<String> names, {double minLikelihood = 0.35}) {
    for (final name in names) {
      final point = points[name];
      if (point == null || point.likelihood < minLikelihood) return false;
    }
    return true;
  }
}

class NuvoPosePoint {
  const NuvoPosePoint({
    required this.x,
    required this.y,
    required this.z,
    required this.likelihood,
  });

  /// Normalized horizontal position from 0.0 to 1.0.
  final double x;

  /// Normalized vertical position from 0.0 to 1.0.
  final double y;

  final double z;
  final double likelihood;
}
