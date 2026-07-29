import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import 'ai_motion_models.dart';
import 'race_api.dart';
import 'race_models.dart';
import 'universal_proof_rule.dart';
import 'vision_observation_models.dart';

class RaceRepository {
  RaceRepository(this._api, this._store, this._authApi);

  final RaceApi _api;
  final SecureTokenStore _store;
  final AuthApi _authApi;

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
    String? visibility,
    String? aiActivityType,
    String? activityId,
    String? metric,
    String? format,
    String? recurrence,
    String? targetUnit,
    String? proofMode,
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
      visibility: visibility,
      aiActivityType: aiActivityType,
      activityId: activityId,
      metric: metric,
      format: format,
      recurrence: recurrence,
      targetUnit: targetUnit,
      proofMode: proofMode,
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
    String? visibility,
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
      visibility: visibility,
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
  }) => _withRefresh(
    (token) => _api.submitProof(
      token,
      raceId,
      proofType: proofType,
      note: note,
      value: value,
    ),
  );

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

  Future<VisionObservation> analyzeVisionObservation(
    String raceId, {
    required String observationId,
    required String activityId,
    required String prompt,
    required String imageBase64,
    String imageMimeType = 'image/jpeg',
  }) => _withRefresh(
    (token) => _api.analyzeVisionObservation(
      token,
      raceId,
      observationId: observationId,
      activityId: activityId,
      prompt: prompt,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    ),
  );

  Future<Race> submitUniversalAiProof(
    String raceId, {
    required String clientSubmissionId,
    required String activityType,
    required String metric,
    required int value,
    required int targetValue,
    required double confidence,
    required String verificationStatus,
    required String verificationSummary,
    required int framesAnalyzed,
    required int validSignalFrames,
    required int durationMs,
    required String validatorVersion,
  }) => _withRefresh(
    (token) => _api.submitUniversalAiProof(
      token,
      raceId,
      clientSubmissionId: clientSubmissionId,
      activityType: activityType,
      metric: metric,
      value: value,
      targetValue: targetValue,
      confidence: confidence,
      verificationStatus: verificationStatus,
      verificationSummary: verificationSummary,
      framesAnalyzed: framesAnalyzed,
      validSignalFrames: validSignalFrames,
      durationMs: durationMs,
      validatorVersion: validatorVersion,
    ),
  );

  Future<UniversalProofRule> buildUniversalProofRule({
    required String actionName,
    required String unit,
    required String positiveImageBase64,
    String? negativeImageBase64,
    String? negativeNote,
    String imageMimeType = 'image/jpeg',
  }) => _withRefresh(
    (token) => _api.buildUniversalProofRule(
      token,
      actionName: actionName,
      unit: unit,
      positiveImageBase64: positiveImageBase64,
      negativeImageBase64: negativeImageBase64,
      negativeNote: negativeNote,
      imageMimeType: imageMimeType,
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
}
