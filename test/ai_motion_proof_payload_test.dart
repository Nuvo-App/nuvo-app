import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_sequence_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Release contract: every AI Motion Proof must carry the server
/// verification session it was produced under — the Worker rejects
/// ai_motion proofs without it. Retries must reuse the SAME session id.
void main() {
  group('AI proof payload carries the verification session', () {
    const result = AiMotionResult(
      activity: AiMotionActivity.pushUps,
      targetReps: 20,
      detectedReps: 6,
      confidence: 0.82,
      verificationStatus: 'ai_verified',
      verificationSummary: 'Detected 6 push-ups from live pose tracking.',
      framesAnalyzed: 40,
      validPoseFrames: 36,
      durationMs: 4000,
      validatorVersion: 'nuvo-ai-motion-v2',
    );

    test('preset motion payload binds the session id', () {
      final payload = result.toProofPayload(
        clientSubmissionId: 'sub-1',
        metric: 'reps',
        verificationSessionId: 'vs-123',
      );
      expect(payload['verificationSessionId'], 'vs-123');
      expect(payload['clientSubmissionId'], 'sub-1');
      expect(payload['proofType'], 'ai_motion');
    });

    test('same session id survives a retry submission', () {
      final first = result.toProofPayload(
        clientSubmissionId: 'sub-1',
        metric: 'reps',
        verificationSessionId: 'vs-123',
      );
      final retry = result.toProofPayload(
        clientSubmissionId: 'sub-1',
        metric: 'reps',
        verificationSessionId: 'vs-123',
      );
      expect(retry['verificationSessionId'], first['verificationSessionId']);
    });

    test('no session → field is omitted, never fabricated', () {
      final payload = result.toProofPayload(
        clientSubmissionId: 'sub-1',
        metric: 'reps',
      );
      expect(payload.containsKey('verificationSessionId'), isFalse);
      expect(payload['clientSubmissionId'], isNotEmpty);
    });

    test('custom pose payload binds the session id', () {
      const custom = CustomPoseRuntimeResult(
        verifierType: 'custom_pose_sequence',
        verifierVersion: 3,
        movementName: 'My Movement',
        measurementType: 'reps',
        count: 8,
        target: 10,
        verificationStatus: 'ai_verified',
        confidence: 0.9,
        framesAnalyzed: 120,
        validFrames: 100,
        durationMs: 8000,
        completionEvents: 8,
        invalidAttemptCount: 0,
        finalFailureReason: null,
      );
      final payload = custom.toProofPayload(
        clientSubmissionId: 'sub-9',
        verificationSessionId: 'vs-456',
      );
      expect(payload['verificationSessionId'], 'vs-456');
    });
  });
}
