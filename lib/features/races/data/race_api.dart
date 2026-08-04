import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart';
import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import 'ai_motion_models.dart';
import 'race_models.dart';

const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);

class RaceApi {
  RaceApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> _get(String path, String token) async {
    final res = await _client.get(
      Uri.parse('$_kApiBase$path'),
      headers: _headers(token),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    final res = await _client.post(
      Uri.parse('$_kApiBase$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    final res = await _client.patch(
      Uri.parse('$_kApiBase$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> _delete(String path, String token) async {
    final res = await _client.delete(
      Uri.parse('$_kApiBase$path'),
      headers: _headers(token),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    return json;
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
    final res = await _client.get(uri, headers: _headers(token));
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
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
