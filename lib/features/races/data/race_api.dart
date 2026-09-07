// HTTP + JSON for race endpoints. One method per endpoint; each takes a `token`.
// Callers go through RaceRepository (token injection + 401 retry), never here
// directly. See docs/agents/03-data-auth-and-backend.md and
// docs/agents/10-pitfalls-and-fixes.md §A1.
//
// EVERY request goes through _guard() (20 s hard timeout → ApiException on
// TimeoutException/SocketException/ClientException) and _decode() (tolerates
// non-JSON / empty error bodies). A raw `_client.get(...)` with no timeout will
// hang a stalled socket forever and wedge the races tab — do not add one.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart';
import '../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import 'ai_motion_models.dart';
import 'motion_analysis_contract.dart';
import 'race_models.dart';

const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);

class RaceApi {
  RaceApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<MotionAnalysisResult> analyzeMotion(
    String token, {
    required MotionAnalysisRequest request,
  }) async {
    final json = await _post('/motion/analyze', token, request.toJson());
    return MotionAnalysisResult.fromJson(
      json['result'] as Map<String, dynamic>,
    );
  }

  /// Uploads one gzip'd [MotionSessionArtifact] plus its searchable metadata.
  /// The Worker stores the blob in R2 and indexes the metadata in D1.
  Future<void> uploadMotionSession(
    String token, {
    required Map<String, dynamic> metadata,
    required Uint8List gzipBytes,
  }) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase/motion-sessions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/gzip',
          'X-Motion-Session': base64Encode(utf8.encode(jsonEncode(metadata))),
        },
        body: gzipBytes,
      ),
    );
    _decode(res);
  }

  Future<void> submitMotionTrainingExample(
    String token, {
    required MotionAnalysisRequest request,
    required String consentVersion,
    String? label,
  }) async {
    final body = request.toJson()
      ..['consentVersion'] = consentVersion
      ..['frames'] = request.frames.map((frame) => frame.toJson()).toList();
    if (label != null) body['label'] = label;
    await _post('/motion/training/examples', token, body);
  }

  /// Every network call fails fast instead of hanging a stalled socket
  /// indefinitely — a hung request used to wedge the whole races tab until the
  /// app was killed.
  static const _requestTimeout = Duration(seconds: 20);

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  /// Runs [send] with a hard timeout and maps transport failures to a clean
  /// [ApiException] the UI can show.
  Future<http.Response> _guard(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiException(
        408,
        'The network timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const ApiException(
        0,
        "Can't reach Nuvo. Check your connection and try again.",
      );
    } on http.ClientException {
      throw const ApiException(
        0,
        "Can't reach Nuvo. Check your connection and try again.",
      );
    }
  }

  /// Decodes a JSON body, tolerating non-JSON error pages (Cloudflare 5xx,
  /// empty bodies) instead of throwing an opaque FormatException.
  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic>? parsed;
    if (res.body.isNotEmpty) {
      try {
        final value = jsonDecode(res.body);
        if (value is Map<String, dynamic>) parsed = value;
      } catch (_) {
        parsed = null;
      }
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        parsed?['error'] as String? ?? 'Request failed',
      );
    }
    return parsed ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _get(String path, String token) async {
    final res = await _guard(
      () => _client.get(Uri.parse('$_kApiBase$path'), headers: _headers(token)),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase$path'),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    final res = await _guard(
      () => _client.patch(
        Uri.parse('$_kApiBase$path'),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> _delete(String path, String token) async {
    final res = await _guard(
      () =>
          _client.delete(Uri.parse('$_kApiBase$path'), headers: _headers(token)),
    );
    return _decode(res);
  }

  Future<List<Race>> getRaces(String token) async {
    final json = await _get('/races', token);
    return (json['races'] as List<dynamic>)
        .map((r) => Race.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<PublicUser>> searchUsers(String token, String query) async {
    final uri = Uri.parse(
      '$_kApiBase/users/search',
    ).replace(queryParameters: {'q': query});
    final res = await _guard(() => _client.get(uri, headers: _headers(token)));
    final json = _decode(res);
    return (json['users'] as List<dynamic>)
        .map((u) => PublicUser.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  Future<List<PublicUser>> getCrew(String token) async {
    final json = await _get('/crew', token);
    return (json['crew'] as List<dynamic>)
        .map((u) => PublicUser.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  Future<PublicUser?> addCrewUser(String token, String userId) async {
    final json = await _post('/crew/add', token, {'userId': userId});
    final user = json['user'];
    return user is Map<String, dynamic> ? PublicUser.fromJson(user) : null;
  }

  Future<void> removeCrewUser(String token, String userId) async {
    await _delete('/crew/$userId', token);
  }

  Future<Race> createRace(
    String token, {
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
  }) async {
    final body = <String, dynamic>{'title': title, 'goalType': goalType};
    if (description != null) body['description'] = description;
    if (category != null) body['category'] = category;
    if (targetValue != null) body['targetValue'] = targetValue;
    if (unit != null) body['unit'] = unit;
    if (startLineAt != null) body['startLineAt'] = startLineAt;
    if (finishLineAt != null) body['finishLineAt'] = finishLineAt;
    if (rules != null) body['rules'] = rules;
    if (proofRequirement != null) body['proofRequirement'] = proofRequirement;
    if (proofReviewMode != null) body['proofReviewMode'] = proofReviewMode;
    if (visibility != null) body['visibility'] = visibility;
    if (aiActivityType != null) body['aiActivityType'] = aiActivityType;
    if (activityId != null) body['activityId'] = activityId;
    if (metric != null) body['metric'] = metric;
    if (format != null) body['format'] = format;
    if (recurrence != null) body['recurrence'] = recurrence;
    if (targetUnit != null) body['targetUnit'] = targetUnit;
    if (proofMode != null) body['proofMode'] = proofMode;
    final json = await _post('/races', token, body);
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> createCustomRace(
    String token, {
    required String title,
    required int targetValue,
    required String customActivityName,
    required CustomPoseVerifierSpec verifierSpec,
  }) async {
    final json = await _post('/races', token, {
      'title': title,
      'goalType': 'first_to_goal',
      'targetValue': targetValue,
      'unit': 'reps',
      'targetUnit': 'reps',
      'metric': 'reps',
      'proofRequirement': 'ai_check',
      'proofReviewMode': 'auto_accept',
      'proofMode': 'ai_check',
      'verificationMethod': 'ai',
      'visibility': 'private',
      'verifierType': customPoseVerifierType,
      'verifierVersion': customPoseVerifierSpecSchemaVersion,
      'customActivityName': customActivityName,
      'verifierSpec': verifierSpec.toJson(),
    });
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> updateRace(
    String token,
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
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (category != null) body['category'] = category;
    if (goalType != null) body['goalType'] = goalType;
    if (targetValue != null) body['targetValue'] = targetValue;
    if (unit != null) body['unit'] = unit;
    if (status != null) body['status'] = status;
    if (startLineAt != null) body['startLineAt'] = startLineAt;
    if (finishLineAt != null) body['finishLineAt'] = finishLineAt;
    if (rules != null) body['rules'] = rules;
    if (proofRequirement != null) body['proofRequirement'] = proofRequirement;
    if (proofReviewMode != null) body['proofReviewMode'] = proofReviewMode;
    if (visibility != null) body['visibility'] = visibility;
    if (aiActivityType != null) body['aiActivityType'] = aiActivityType;
    if (targetUnit != null) body['targetUnit'] = targetUnit;
    if (proofMode != null) body['proofMode'] = proofMode;
    final json = await _patch('/races/$id', token, body);
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> getRaceDetail(String token, String id) async {
    final json = await _get('/races/$id', token);
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> submitProof(
    String token,
    String raceId, {
    String proofType = 'manual',
    String? note,
    required int value,
  }) async {
    final body = <String, dynamic>{'proofType': proofType, 'value': value};
    if (note != null) body['note'] = note;
    final json = await _post('/races/$raceId/proof', token, body);
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> submitAiMotionProof(
    String token,
    String raceId, {
    required AiMotionResult result,
    required String clientSubmissionId,
    required String metric,
  }) async {
    final json = await _post(
      '/races/$raceId/proof',
      token,
      result.toProofPayload(
        clientSubmissionId: clientSubmissionId,
        metric: metric,
      ),
    );
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> submitCustomPoseProof(
    String token,
    String raceId, {
    required CustomPoseRuntimeResult result,
    required String clientSubmissionId,
  }) async {
    final json = await _post(
      '/races/$raceId/proof',
      token,
      result.toProofPayload(clientSubmissionId: clientSubmissionId),
    );
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> archiveRace(String token, String id) async {
    final json = await _post('/races/$id/archive', token, {});
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> cancelRace(String token, String id) async {
    final json = await _post('/races/$id/cancel', token, {});
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<void> deleteRace(String token, String id) async {
    await _delete('/races/$id', token);
  }

  Future<void> leaveRace(String token, String id) async {
    await _post('/races/$id/leave', token, {});
  }

  Future<Race> joinRace(String token, String id) async {
    final json = await _post('/races/$id/join', token, {});
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> addRaceParticipant(
    String token,
    String raceId,
    String userId,
  ) async {
    final json = await _post('/races/$raceId/participants', token, {
      'userId': userId,
    });
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<String> createInviteCode(String token, String id) async {
    final json = await _post('/races/$id/invite-code', token, {});
    return json['inviteCode'] as String;
  }

  Future<Race> joinRaceByCode(String token, String code) async {
    final json = await _post('/races/join-code', token, {'code': code});
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }

  Future<Race> reviewProof(
    String token,
    String raceId,
    String proofId, {
    required String status,
    String? summary,
  }) async {
    final body = <String, dynamic>{'verificationStatus': status};
    if (summary != null) body['verificationSummary'] = summary;
    final json = await _patch('/races/$raceId/proofs/$proofId', token, body);
    return Race.fromJson(json['race'] as Map<String, dynamic>);
  }
}
