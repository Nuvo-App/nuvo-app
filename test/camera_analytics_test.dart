// Camera analytics wiring (docs/ANALYTICS.md event table). The three camera
// funnel events go through AnalyticsService helpers only: `camera_ready`
// once at the first live preview, `calibration_failed` once per take that
// ends unverified, and `proof_result` once per landed/thrown submit on the
// RaceController seams. The camera screen can't run in a widget test (no
// camera), so its emit sites are pinned as a source contract — the same
// approach proof_pipeline_test.dart uses — while the controller seam is
// exercised for real with FakeAnalyticsService.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

const _result = AiMotionResult(
  activity: AiMotionActivity.squats,
  targetReps: 20,
  detectedReps: 8,
  confidence: 0.9,
  verificationStatus: 'ai_verified',
  verificationSummary: 'ok',
  framesAnalyzed: 100,
  validPoseFrames: 90,
  durationMs: 5000,
  validatorVersion: 'v1',
);

/// The submit response — the just-posted proof lands as recentProofs.first,
/// the same read _emitProofOutcome makes.
Race _submittedRace({String status = 'ai_verified', int detected = 42}) =>
    Race.fromJson({
      'id': 'r1',
      'creatorId': 'u-rival',
      'title': 'Pushup race',
      'format': 'first_to_goal',
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
      'recentProofs': [
        {
          'id': 'p1',
          'userId': 'u-me',
          'displayName': 'Me',
          'proofType': 'ai_motion',
          'detectedValue': detected,
          'verificationStatus': status,
          'createdAt': '2026-01-01T00:00:00Z',
        },
      ],
      'submissionResult': {
        'verifiedValue': detected,
        'previousScore': 0,
        'newScore': detected,
        'peoplePassed': 0,
        'raceCompleted': false,
      },
    });

/// Repo that returns scripted proof outcomes — same shape as
/// proof_pipeline_test.dart's controller fake, minus the session calls.
class _FakeRepo extends RaceRepository {
  _FakeRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  List<Race> listed = const [];
  Race? proofResponse;
  Object? proofError;
  int submitCalls = 0;

  @override
  Future<Conditional<List<Race>>> getRacesConditional({String? etag}) async =>
      Conditional(data: listed, etag: '"e1"', raw: const []);

  @override
  Future<RaceAttemptResult> startAttempt(
    String raceId, {
    String? clientAttemptId,
  }) async => const RaceAttemptResult(
    attemptId: 'att-1',
    attemptIndex: 1,
    status: 'open',
    attemptsUsed: 0,
  );

  @override
  Future<Race> submitAiMotionProof(
    String raceId, {
    required AiMotionResult result,
    required String clientSubmissionId,
    required String metric,
    String? verificationSessionId,
    ProofSessionResult? sessionResult,
  }) async {
    submitCalls++;
    if (proofError != null) throw proofError!;
    return proofResponse!;
  }
}

void main() {
  group('proof_result via controller seams', () {
    Future<(RaceController, FakeAnalyticsService)> setup({
      Race? response,
      Object? error,
    }) async {
      final repo = _FakeRepo()
        ..listed = [_submittedRace()]
        ..proofResponse = response ?? _submittedRace()
        ..proofError = error;
      final analytics = FakeAnalyticsService();
      final controller = RaceController(repo, analytics: analytics);
      await controller.loadRaces(force: true);
      return (controller, analytics);
    }

    test('fires exactly once when an AI Motion submit lands', () async {
      final (controller, analytics) = await setup();

      await controller.startAttempt('r1', clientAttemptId: 'att-1');
      await controller.submitAiMotionProof(
        'r1',
        result: _result,
        clientSubmissionId: 'sub-1',
        metric: 'reps',
      );

      final results = analytics.events
          .where((e) => e.event == 'proof_result')
          .toList();
      expect(results, hasLength(1), reason: 'one proof_result per submit');
      final props = results.single.properties;
      expect(props['outcome'], 'verified');
      expect(props['detected_value'], '10-49'); // bucketed, not the raw 42
      expect(props['duration_s'], isA<int>());
      expect(props['failure_reason'], isNull); // no reason on a verdict
      expect(
        props.keys.toSet().difference(AnalyticsService.allowedProperties),
        isEmpty,
        reason: 'proof_result carried a non-allowlisted property',
      );
      // race_started stays on the attempt seam: one per open, and the
      // submit path's silent ensure-open never re-emits it.
      expect(
        analytics.events.where((e) => e.event == 'race_started'),
        hasLength(1),
      );
    });

    test('fires exactly once with http_<status> when the submit throws',
        () async {
      final (controller, analytics) = await setup(
        error: const ApiException(409, 'session already used'),
      );

      await expectLater(
        controller.submitAiMotionProof(
          'r1',
          result: _result,
          clientSubmissionId: 'sub-2',
          metric: 'reps',
        ),
        throwsA(isA<ApiException>()),
      );

      final results = analytics.events
          .where((e) => e.event == 'proof_result')
          .toList();
      expect(results, hasLength(1));
      final props = results.single.properties;
      expect(props['outcome'], 'submit_failed');
      expect(props['failure_reason'], 'http_409');
      expect(
        props.keys.toSet().difference(AnalyticsService.allowedProperties),
        isEmpty,
      );
      // The transport failure also lands on the capped error channel.
      expect(
        analytics.events.where((e) => e.event == 'api_error'),
        hasLength(1),
      );
    });
  });

  group('ai_motion_proof_screen_io call sites (source contract)', () {
    final src = File(
      'lib/features/races/presentation/ai_motion_proof_screen_io.dart',
    ).readAsStringSync();

    test('camera_ready fires once at the first live preview', () {
      final init = src.indexOf('Future<void> _initializeCamera(');
      expect(init, greaterThan(-1));
      // The emit lands inside _initializeCamera, on the success path that
      // first sets the ready state.
      final emit = src.indexOf('_trackCameraReadyOnce();', init);
      final ready = src.indexOf('AiMotionProofStatus.cameraReady', init);
      expect(emit, greaterThan(init));
      expect(emit, lessThan(ready));
      // Once per screen open: a guard wraps the emit, and ms is measured
      // from the screen-open clock.
      expect(src, contains('_cameraReadyTracked'));
      expect(src, contains('_screenOpenedAt'));
      expect(src, contains('cameraReady('));
    });

    test('calibration_failed fires at each unverified finish transition',
        () {
      // One emit helper plus the three aiFailed branches in
      // _finishRecording: object composition, custom pose, preset/remote.
      expect('_trackCalibrationFailed('.allMatches(src), hasLength(4));
      expect(
        src,
        contains(
          "_trackCalibrationFailed(update?.diagnostic ?? 'shot_not_confirmed')",
        ),
      );
      expect(src, contains('acceptedResult.finalFailureReason'));
      expect(
        src,
        contains('_trackCalibrationFailed(_runtime.failedRuleReason)'),
      );
      // Enum reasons only — never a user-facing or exception message.
      expect(src, isNot(contains('calibrationFailed(reason: _message')));
      expect(src, contains("'unknown'"));
    });

    test('proof_result stays on the controller submit seams', () {
      expect(src, isNot(contains('proofResult(')));
      // Helpers only — no raw track() in the camera file.
      expect(src, isNot(contains('.track(')));
    });
  });
}
