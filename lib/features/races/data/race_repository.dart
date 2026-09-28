import 'dart:typed_data';

import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import '../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import 'ai_motion_models.dart';
import 'motion_analysis_contract.dart';
import 'race_api.dart';
import 'race_models.dart';

class RaceRepository {
  RaceRepository(this._api, this._store, this._authApi);

  final RaceApi _api;
  final SecureTokenStore _store;
  final AuthApi _authApi;

  Future<MotionAnalysisResult> analyzeMotion(MotionAnalysisRequest request) =>
      _withRefresh((token) => _api.analyzeMotion(token, request: request));

  Future<MotionModelArtifactFetch> getMotionModelArtifact(
    String modelVersion, {
    String? etag,
  }) => _withRefresh(
    (token) => _api.getMotionModelArtifact(token, modelVersion, etag: etag),
  );

  Future<Map<String, dynamic>?> getCurrentMotionModel({
    required String family,
    String channel = 'stable',
  }) => _withRefresh(
    (token) => _api.getCurrentMotionModel(token, family: family, channel: channel),
  );

  Future<VerificationSessionHandshake> createVerificationSession(
    String raceId, {
    required String appVersion,
    required String appBuild,
    required Set<String> runtimeCapabilities,
  }) => _withRefresh(
    (token) => _api.createVerificationSession(
      token,
      raceId,
      appVersion: appVersion,
      appBuild: appBuild,
      runtimeCapabilities: runtimeCapabilities,
    ),
  );

  Future<VerificationSession> startVerificationSession(String sessionId) =>
      _withRefresh((token) => _api.startVerificationSession(token, sessionId));

  Future<VerificationSession> completeVerificationSession(
    String sessionId, {
    required String releaseId,
    required String releaseChecksum,
    required String status,
    required int resultValue,
    required double confidence,
    String? failureReason,
    String? motionSessionId,
  }) => _withRefresh(
    (token) => _api.completeVerificationSession(
      token,
      sessionId,
      releaseId: releaseId,
      releaseChecksum: releaseChecksum,
      status: status,
      resultValue: resultValue,
      confidence: confidence,
      failureReason: failureReason,
      motionSessionId: motionSessionId,
    ),
  );

  Future<void> uploadMotionSession({
    required Map<String, dynamic> metadata,
    required Uint8List gzipBytes,
  }) => _withRefresh(
    (token) => _api.uploadMotionSession(
      token,
      metadata: metadata,
      gzipBytes: gzipBytes,
    ),
  );

  Future<void> submitMotionTrainingExample({
    required MotionAnalysisRequest request,
    required String consentVersion,
    String? label,
  }) => _withRefresh(
    (token) => _api.submitMotionTrainingExample(
      token,
      request: request,
      consentVersion: consentVersion,
      label: label,
    ),
  );

  Future<T> _withRefresh<T>(Future<T> Function(String token) call) async {
    final token = await _store.getAccessToken();
    if (token == null) throw const ApiException(401, 'Not authenticated');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final refreshToken = await _store.getRefreshToken();
      if (refreshToken == null) {
        await _store.clear();
        rethrow;
      }
      final newToken = await _authApi.refreshSession(refreshToken);
      await _store.saveAccessToken(newToken);
      return await call(newToken);
    }
  }

  Future<List<Race>> getRaces() => _withRefresh(_api.getRaces);

  Future<List<PublicUser>> searchUsers(String query) =>
      _withRefresh((token) => _api.searchUsers(token, query));

  Future<List<PublicUser>> getCrew() => _withRefresh(_api.getCrew);

  Future<PublicUser?> addCrewUser(String userId) =>
      _withRefresh((token) => _api.addCrewUser(token, userId));

  Future<void> removeCrewUser(String userId) =>
      _withRefresh((token) => _api.removeCrewUser(token, userId));

  Future<Race> createRace({
    required String title,
    String? description,
    String? category,
    String goalType = 'manual',
    int? targetValue,
    String? unit,
    String? startLineAt,
    String? finishLineAt,
    String? rules,
    String? proofRequirement,
    String? proofReviewMode,
    String? aiActivityType,
    String? activityId,
    String? metric,
    String? format,
    String? recurrence,
    String? targetUnit,
    String? proofMode,
    String? scoreDirection,
  }) => _withRefresh(
    (token) => _api.createRace(
      token,
      title: title,
      description: description,
      category: category,
      goalType: goalType,
      targetValue: targetValue,
      unit: unit,
      startLineAt: startLineAt,
      finishLineAt: finishLineAt,
      rules: rules,
      proofRequirement: proofRequirement,
      proofReviewMode: proofReviewMode,
      aiActivityType: aiActivityType,
      activityId: activityId,
      metric: metric,
      format: format,
      recurrence: recurrence,
      targetUnit: targetUnit,
      proofMode: proofMode,
      scoreDirection: scoreDirection,
    ),
  );

  Future<Race> createCustomRace({
    required String title,
    required int targetValue,
    required String customActivityName,
    required CustomPoseVerifierSpec verifierSpec,
  }) => _withRefresh(
    (token) => _api.createCustomRace(
      token,
      title: title,
      targetValue: targetValue,
      customActivityName: customActivityName,
      verifierSpec: verifierSpec,
    ),
  );

  Future<Race> updateRace(
    String id, {
    String? title,
    String? description,
    String? category,
    String? goalType,
    int? targetValue,
    String? unit,
    String? status,
    String? startLineAt,
    String? finishLineAt,
    String? rules,
    String? proofRequirement,
    String? proofReviewMode,
    String? aiActivityType,
    String? targetUnit,
    String? proofMode,
  }) => _withRefresh(
    (token) => _api.updateRace(
      token,
      id,
      title: title,
      description: description,
      category: category,
      goalType: goalType,
      targetValue: targetValue,
      unit: unit,
      status: status,
      startLineAt: startLineAt,
      finishLineAt: finishLineAt,
      rules: rules,
      proofRequirement: proofRequirement,
      proofReviewMode: proofReviewMode,
      aiActivityType: aiActivityType,
      targetUnit: targetUnit,
      proofMode: proofMode,
    ),
  );

  Future<Race> getRaceDetail(String id) =>
      _withRefresh((token) => _api.getRaceDetail(token, id));

  Future<Race> submitProof(
    String raceId, {
    String proofType = 'manual',
    String? note,
    required int value,
    String? mediaObjectKey,
  }) => _withRefresh(
    (token) => _api.submitProof(
      token,
      raceId,
      proofType: proofType,
      note: note,
      value: value,
      mediaObjectKey: mediaObjectKey,
    ),
  );

  /// Step 1 of proof evidence upload — signed URL + object key for this race.
  Future<({String uploadUrl, String key})> requestProofMediaUploadUrl(
    String raceId, {
    required String fileName,
    required String contentType,
  }) => _withRefresh(
    (token) => _api.requestProofMediaUploadUrl(
      token,
      raceId,
      fileName: fileName,
      contentType: contentType,
    ),
  );

  /// Step 2 — PUT the bytes to the signed URL. Same stack as profile photos:
  /// the URL signature is the credential, so no Bearer header is needed.
  Future<void> uploadProofMediaBytes(
    String signedUrl,
    Uint8List bytes,
    String contentType,
  ) => _authApi.uploadBytesToSignedUrl(signedUrl, bytes, contentType);

  Future<Race> submitAiMotionProof(
    String raceId, {
    required AiMotionResult result,
    required String clientSubmissionId,
    required String metric,
  }) => _withRefresh(
    (token) => _api.submitAiMotionProof(
      token,
      raceId,
      result: result,
      clientSubmissionId: clientSubmissionId,
      metric: metric,
    ),
  );

  Future<Race> submitCustomPoseProof(
    String raceId, {
    required CustomPoseRuntimeResult result,
    required String clientSubmissionId,
  }) => _withRefresh(
    (token) => _api.submitCustomPoseProof(
      token,
      raceId,
      result: result,
      clientSubmissionId: clientSubmissionId,
    ),
  );

  Future<Race> submitObjectCompositionProof(
    String raceId, {
    required String activityId,
    required String clientSubmissionId,
    required String metric,
    required int value,
    required int targetValue,
    required double confidence,
    required String verificationSummary,
    required String validatorVersion,
    required int framesAnalyzed,
    required int durationMs,
  }) => _withRefresh(
    (token) => _api.submitObjectCompositionProof(
      token,
      raceId,
      activityId: activityId,
      clientSubmissionId: clientSubmissionId,
      metric: metric,
      value: value,
      targetValue: targetValue,
      confidence: confidence,
      verificationSummary: verificationSummary,
      validatorVersion: validatorVersion,
      framesAnalyzed: framesAnalyzed,
      durationMs: durationMs,
    ),
  );

  Future<Race> archiveRace(String id) =>
      _withRefresh((token) => _api.archiveRace(token, id));

  Future<Race> cancelRace(String id) =>
      _withRefresh((token) => _api.cancelRace(token, id));

  Future<void> deleteRace(String id) =>
      _withRefresh((token) => _api.deleteRace(token, id));

  Future<void> leaveRace(String id) =>
      _withRefresh((token) => _api.leaveRace(token, id));

  Future<Race> joinRace(String id) =>
      _withRefresh((token) => _api.joinRace(token, id));

  Future<Race> addRaceParticipant(String raceId, String userId) =>
      _withRefresh((token) => _api.addRaceParticipant(token, raceId, userId));

  Future<String> createInviteCode(String id) =>
      _withRefresh((token) => _api.createInviteCode(token, id));

  Future<Race> joinRaceByCode(String code) =>
      _withRefresh((token) => _api.joinRaceByCode(token, code));

  Future<Race> reviewProof(
    String raceId,
    String proofId, {
    required String status,
    String? summary,
  }) => _withRefresh(
    (token) => _api.reviewProof(
      token,
      raceId,
      proofId,
      status: status,
      summary: summary,
    ),
  );

  Future<RaceAttemptResult> startAttempt(
    String raceId, {
    String? clientAttemptId,
  }) => _withRefresh(
    (token) =>
        _api.startAttempt(token, raceId, clientAttemptId: clientAttemptId),
  );

  Future<Race> rematchRace(String raceId) =>
      _withRefresh((token) => _api.rematchRace(token, raceId));

  Future<RaceLiveState> getRaceLiveState(String raceId, {int? version}) =>
      _withRefresh(
        (token) => _api.getRaceLiveState(token, raceId, version: version),
      );
}
