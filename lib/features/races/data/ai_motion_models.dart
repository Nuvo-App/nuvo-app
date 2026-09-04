enum AiMotionActivity {
  jumpingJacks,
  squats,
  highKnees,
  armRaises,
  plankHold,
  pushUps,
  lunges,
  sumoSquats,
  sideLunges,
  deepSquats,
  squatJacks,
  jumpSquats,
  lungeJumps,
  runningInPlace,
  treadmillRunning,
  walkingInPlace,
  marchingInPlace,
  buttKicks,
  mountainClimbers,
  burpees,
  stepUps,
  calfRaises,
  lateralSteps;

  String get backendValue => switch (this) {
    AiMotionActivity.jumpingJacks => 'jumping_jacks',
    AiMotionActivity.squats => 'squats',
    AiMotionActivity.highKnees => 'high_knees',
    AiMotionActivity.armRaises => 'arm_raises',
    AiMotionActivity.plankHold => 'plank_hold',
    AiMotionActivity.pushUps => 'push_ups',
    AiMotionActivity.lunges => 'lunges',
    AiMotionActivity.sumoSquats => 'sumo_squats',
    AiMotionActivity.sideLunges => 'side_lunges',
    AiMotionActivity.deepSquats => 'deep_squats',
    AiMotionActivity.squatJacks => 'squat_jacks',
    AiMotionActivity.jumpSquats => 'jump_squats',
    AiMotionActivity.lungeJumps => 'lunge_jumps',
    AiMotionActivity.runningInPlace => 'running_in_place',
    AiMotionActivity.treadmillRunning => 'treadmill_running',
    AiMotionActivity.walkingInPlace => 'walking_in_place',
    AiMotionActivity.marchingInPlace => 'marching_in_place',
    AiMotionActivity.buttKicks => 'butt_kicks',
    AiMotionActivity.mountainClimbers => 'mountain_climbers',
    AiMotionActivity.burpees => 'burpees',
    AiMotionActivity.stepUps => 'step_ups',
    AiMotionActivity.calfRaises => 'calf_raises',
    AiMotionActivity.lateralSteps => 'lateral_steps',
  };

  String get label => switch (this) {
    AiMotionActivity.jumpingJacks => 'jumping jacks',
    AiMotionActivity.squats => 'squats',
    AiMotionActivity.highKnees => 'high knees',
    AiMotionActivity.armRaises => 'arm raises',
    AiMotionActivity.plankHold => 'seconds of plank',
    AiMotionActivity.pushUps => 'push-ups',
    AiMotionActivity.lunges => 'lunges',
    AiMotionActivity.sumoSquats => 'sumo squats',
    AiMotionActivity.sideLunges => 'side lunges',
    AiMotionActivity.deepSquats => 'deep squats',
    AiMotionActivity.squatJacks => 'squat jacks',
    AiMotionActivity.jumpSquats => 'jump squats',
    AiMotionActivity.lungeJumps => 'lunge jumps',
    AiMotionActivity.runningInPlace => 'running in place',
    AiMotionActivity.treadmillRunning => 'treadmill running',
    AiMotionActivity.walkingInPlace => 'walking in place',
    AiMotionActivity.marchingInPlace => 'marching in place',
    AiMotionActivity.buttKicks => 'butt kicks',
    AiMotionActivity.mountainClimbers => 'mountain climbers',
    AiMotionActivity.burpees => 'burpees',
    AiMotionActivity.stepUps => 'step-ups',
    AiMotionActivity.calfRaises => 'calf raises',
    AiMotionActivity.lateralSteps => 'lateral steps',
  };

  static AiMotionActivity fromBackendValue(String value) => switch (value) {
    'squats' => AiMotionActivity.squats,
    'high_knees' => AiMotionActivity.highKnees,
    'arm_raises' => AiMotionActivity.armRaises,
    'plank_hold' => AiMotionActivity.plankHold,
    'push_ups' || 'pushups' => AiMotionActivity.pushUps,
    'lunges' || 'lunge' => AiMotionActivity.lunges,
    'sumo_squats' || 'sumo squats' => AiMotionActivity.sumoSquats,
    'side_lunges' || 'side lunges' => AiMotionActivity.sideLunges,
    'deep_squats' || 'deep squats' => AiMotionActivity.deepSquats,
    'squat_jacks' || 'squat jacks' => AiMotionActivity.squatJacks,
    'jump_squats' || 'jump squats' => AiMotionActivity.jumpSquats,
    'lunge_jumps' || 'lunge jumps' => AiMotionActivity.lungeJumps,
    'running_in_place' || 'running in place' =>
      AiMotionActivity.runningInPlace,
    'treadmill_running' || 'treadmill running' =>
      AiMotionActivity.treadmillRunning,
    'walking_in_place' || 'walking in place' =>
      AiMotionActivity.walkingInPlace,
    'marching_in_place' || 'marching in place' =>
      AiMotionActivity.marchingInPlace,
    'butt_kicks' || 'butt kicks' => AiMotionActivity.buttKicks,
    'mountain_climbers' || 'mountain climbers' =>
      AiMotionActivity.mountainClimbers,
    'burpees' || 'burpee' => AiMotionActivity.burpees,
    'step_ups' || 'step ups' || 'step-ups' => AiMotionActivity.stepUps,
    'calf_raises' || 'calf raises' => AiMotionActivity.calfRaises,
    'lateral_steps' ||
    'lateral steps' ||
    'side_steps' ||
    'side steps' =>
      AiMotionActivity.lateralSteps,
    _ => AiMotionActivity.pushUps,
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
  unsupportedMovement,
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
  bool get isHold => activity == AiMotionActivity.plankHold;

  Map<String, dynamic> toProofPayload({
    required String clientSubmissionId,
    required String metric,
  }) => {
    'proofType': 'ai_motion',
    'clientSubmissionId': clientSubmissionId,
    'activityType': activity.backendValue,
    'metric': metric,
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
