import '../data/ai_motion_models.dart';

class PushUpCounter {
  const PushUpCounter();

  AiMotionResult unsupportedResult({required int targetReps}) => AiMotionResult(
    activity: AiMotionActivity.pushUps,
    targetReps: targetReps,
    detectedReps: 0,
    confidence: 0,
    verificationStatus: 'needs_review',
    verificationSummary:
        'Push-up motion proof is experimental and is not enabled for v1.',
    framesAnalyzed: 0,
    validPoseFrames: 0,
    durationMs: 0,
    validatorVersion: JumpingJackCounterVersion.placeholder,
  );
}

abstract final class JumpingJackCounterVersion {
  static const placeholder = 'nuvo-ai-motion-v1-push-up-placeholder';
}
