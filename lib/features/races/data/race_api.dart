// HTTP + JSON for race endpoints. One method per endpoint; each takes a `token`.
// Callers go through RaceRepository (token injection + 401 retry), never here
// directly. See docs/agents/03-data-auth-and-backend.md and
// docs/agents/10-pitfalls-and-fixes.md §A1.
//
// EVERY request goes through _guard() (20 s hard timeout → ApiException on
// TimeoutException/SocketException/ClientException) and _decode() (tolerates
// non-JSON / empty error bodies). A raw `_client.get(...)` with no timeout will
// hang a stalled socket forever and wedge the races tab — do not add one.
import 'package:nuvo/core/utils/json_safe.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart';
import '../ai/custom_pose/custom_pose_sequence_runtime.dart';
import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../ai/motion_v2/motion_v2_models.dart';
import '../ai/motion_v2/motion_v2_verifier_runtime.dart';
import 'ai_motion_models.dart';
import 'motion_analysis_contract.dart';
import 'race_models.dart';
import '../../../core/network/api_base.dart';
import '../../../core/network/conditional.dart';

class MotionCatalogFetch {
  const MotionCatalogFetch({this.json, this.etag, this.notModified = false});

  final Map<String, dynamic>? json;
  final String? etag;
  final bool notModified;
}

class MotionReleaseFetch {
  const MotionReleaseFetch({this.json, this.etag, this.notModified = false});

  final Map<String, dynamic>? json;
  final String? etag;
  final bool notModified;
}

class MotionModelArtifactFetch {
  const MotionModelArtifactFetch({
    this.bytes,
    this.etag,
    this.modelVersion,
    this.sha256,
    this.notModified = false,
  });

  final Uint8List? bytes;
  final String? etag;
  final String? modelVersion;
  final String? sha256;
  final bool notModified;
}

class VerificationSession {
  const VerificationSession({
    required this.id,
    required this.raceId,
    required this.activityId,
    required this.releaseId,
    required this.releaseChecksum,
    required this.status,
  });

  factory VerificationSession.fromJson(Map<String, dynamic> json) =>
      VerificationSession(
        id: json['id'] as String? ?? '',
        raceId: json['raceId'] as String? ?? '',
        activityId: json['activityId'] as String? ?? '',
        releaseId: json['releaseId'] as String? ?? '',
        releaseChecksum:
            json['releaseChecksum'] as String? ??
            json['checksum'] as String? ??
            '',
        status: json['status'] as String? ?? 'created',
      );

  final String id;
  final String raceId;
  final String activityId;
  final String releaseId;
  final String releaseChecksum;
  final String status;
}

/// The client's own account of a finished verification session, sent next to
/// `verificationSessionId` in `POST /races/:id/proof`. When the session is
/// still created/running and the release id + checksum match, the server
/// completes the session itself in the same request. Older servers ignore it.
class ProofSessionResult {
  const ProofSessionResult({
    required this.releaseId,
    required this.releaseChecksum,
    required this.resultValue,
    this.confidence,
    this.motionSessionId,
  });

  final String releaseId;
  final String releaseChecksum;
  final int resultValue;
  final double? confidence;
  final String? motionSessionId;

  Map<String, dynamic> toJson() => {
    'releaseId': releaseId,
    'releaseChecksum': releaseChecksum,
    'resultValue': resultValue,
    'confidence': ?confidence,
    'motionSessionId': ?motionSessionId,
  };
}

/// True for failures worth retrying with the SAME clientSubmissionId: the
/// request may never have reached the server (timeout / no network) or the
/// server failed (5xx). A 4xx is a definitive answer and is never retried.
bool isRetryableProofFailure(Object error) =>
    error is ApiException &&
    (error.statusCode == 0 ||
        error.statusCode == 408 ||
        error.statusCode >= 500);

class VerificationSessionHandshake {
  const VerificationSessionHandshake({
    required this.session,
    required this.verifier,
  });

  final VerificationSession session;
  final Map<String, dynamic> verifier;
}

/// [ApiException] that also carries the Worker's machine-readable `code` and
/// the offending `field`, when the error body includes them. The message is
/// always the server's friendly `error` text.
class RaceApiException extends ApiException {
  const RaceApiException(
    super.statusCode,
    super.message, {
    this.code,
    this.field,
  });

  final String? code;
  final String? field;

  @override
  String toString() =>
      'ApiException $statusCode: $message${code == null ? '' : ' [$code]'}'
      '${field == null ? '' : ' (field: $field)'}';
}

class RaceApi {
  RaceApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<MotionCatalogFetch> getMotionCatalog({String? etag}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/races/activities'),
        headers: headers,
      ),
    );
    if (res.statusCode == 304) {
      return MotionCatalogFetch(
        etag: res.headers['etag'] ?? etag,
        notModified: true,
      );
    }
    final json = _decode(res);
    return MotionCatalogFetch(json: json, etag: res.headers['etag']);
  }

  Future<MotionReleaseFetch> getMotionRelease(
    String releaseId, {
    String? etag,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/motion/releases/$releaseId'),
        headers: headers,
      ),
    );
    if (res.statusCode == 304) {
      return MotionReleaseFetch(
        etag: res.headers['etag'] ?? etag,
        notModified: true,
      );
    }
    final json = _decode(res);
    final release = json['release'];
    if (release is! Map<String, dynamic>) {
      throw const ApiException(
        502,
        'Verifier release response was incomplete.',
      );
    }
    return MotionReleaseFetch(json: release, etag: res.headers['etag']);
  }

  Future<MotionModelArtifactFetch> getMotionModelArtifact(
    String token,
    String modelVersion, {
    String? etag,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/octet-stream',
      'Authorization': 'Bearer $token',
    };
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/motion/models/$modelVersion/artifact'),
        headers: headers,
      ),
    );
    if (res.statusCode == 304) {
      return MotionModelArtifactFetch(
        etag: res.headers['etag'] ?? etag,
        modelVersion: res.headers['x-model-version'],
        sha256: res.headers['x-model-sha256'],
        notModified: true,
      );
    }
    if (res.statusCode >= 400) _decode(res);
    if (res.bodyBytes.isEmpty) {
      throw const ApiException(502, 'Model artifact response was empty.');
    }
    return MotionModelArtifactFetch(
      bytes: Uint8List.fromList(res.bodyBytes),
      etag: res.headers['etag'],
      modelVersion: res.headers['x-model-version'],
      sha256: res.headers['x-model-sha256'],
    );
  }

  /// Resolves the current remote model release for a family and channel.
  /// Returns null when no release is published — callers fall back to their
  /// last-known-good cache, then to the bundled artifact.
  Future<Map<String, dynamic>?> getCurrentMotionModel(
    String token, {
    required String family,
    String channel = 'stable',
  }) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse(
          '$kNuvoApiBase/motion/models/current?family=$family&channel=$channel',
        ),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
    );
    if (res.statusCode >= 400) _decode(res);
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(
        502,
        'Model resolution response was incomplete.',
      );
    }
    final model = decoded['model'];
    if (model == null) return null;
    if (model is! Map<String, dynamic>) {
      throw const ApiException(502, 'Model resolution response was malformed.');
    }
    return model;
  }

  Future<VerificationSessionHandshake> createVerificationSession(
    String token,
    String raceId, {
    required String appVersion,
    required String appBuild,
    required Set<String> runtimeCapabilities,
  }) async {
    final json = await _post('/races/$raceId/verification-sessions', token, {
      'appVersion': appVersion,
      'appBuild': appBuild,
      'runtimeCapabilities': runtimeCapabilities.toList()..sort(),
    });
    final rawSession = json['session'];
    final rawVerifier = json['verifier'];
    if (rawSession is! Map<String, dynamic> ||
        rawVerifier is! Map<String, dynamic>) {
      throw const ApiException(
        502,
        'Verifier session response was incomplete.',
      );
    }
    return VerificationSessionHandshake(
      session: VerificationSession.fromJson(rawSession),
      verifier: rawVerifier,
    );
  }

  /// Not called by the AI Motion Proof flow any more (`complete` accepts a
  /// `created` session); kept for older code paths.
  Future<VerificationSession> startVerificationSession(
    String token,
    String sessionId,
  ) async {
    final json = await _post(
      '/verification-sessions/$sessionId/start',
      token,
      const {},
    );
    return VerificationSession.fromJson(_requireMap(json['session']));
  }

  Future<VerificationSession> completeVerificationSession(
    String token,
    String sessionId, {
    required String releaseId,
    required String releaseChecksum,
    required String status,
    required int resultValue,
    required double confidence,
    String? failureReason,
    String? motionSessionId,
  }) async {
    final body = <String, dynamic>{
      'releaseId': releaseId,
      'releaseChecksum': releaseChecksum,
      'status': status,
      'resultValue': resultValue,
      'confidence': confidence,
      if (failureReason != null && failureReason.isNotEmpty)
        'failureReason': failureReason,
      'motionSessionId': ?motionSessionId,
    };
    final json = await _post(
      '/verification-sessions/$sessionId/complete',
      token,
      body,
    );
    return VerificationSession.fromJson(_requireMap(json['session']));
  }

  Future<MotionAnalysisResult> analyzeMotion(
    String token, {
    required MotionAnalysisRequest request,
  }) async {
    final json = await _post('/motion/analyze', token, request.toJson());
    return MotionAnalysisResult.fromJson(_requireMap(json['result']));
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
        Uri.parse('$kNuvoApiBase/motion-sessions'),
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

  /// Uploads one gzip'd Teach Nuvo diagnostic session plus its searchable
  /// metadata — same transport as [uploadMotionSession], indexed in
  /// `motion_teach_sessions` instead.
  Future<void> uploadTeachSession(
    String token, {
    required Map<String, dynamic> metadata,
    required Uint8List gzipBytes,
  }) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase/teach-sessions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/gzip',
          'X-Teach-Session': base64Encode(utf8.encode(jsonEncode(metadata))),
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
    } on HandshakeException {
      throw const ApiException(
        0,
        "Can't reach Nuvo. Check your connection and try again.",
      );
    } on TlsException {
      throw const ApiException(
        0,
        "Can't reach Nuvo. Check your connection and try again.",
      );
    } on IOException {
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

  /// A response field that must be a JSON object; anything else is a 502.
  Map<String, dynamic> _requireMap(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    throw const ApiException(502, 'Something went wrong. Try again.');
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
      final friendly = jStr(parsed?['error']);
      throw RaceApiException(
        res.statusCode,
        (friendly == null || friendly.trim().isEmpty)
            ? 'Request failed'
            : friendly,
        code: jStr(parsed?['code']),
        field: jStr(parsed?['field']),
      );
    }
    return parsed ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _get(String path, String token) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase$path'),
        headers: _headers(token),
      ),
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
        Uri.parse('$kNuvoApiBase$path'),
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
        Uri.parse('$kNuvoApiBase$path'),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> _delete(String path, String token) async {
    final res = await _guard(
      () => _client.delete(
        Uri.parse('$kNuvoApiBase$path'),
        headers: _headers(token),
      ),
    );
    return _decode(res);
  }

  Future<Conditional<List<Race>>> getRaces(String token, {String? etag}) async {
    final res = await _conditionalGet('/races', token, etag);
    if (res.statusCode == 304) {
      return Conditional.notModified(etag: res.headers['etag'] ?? etag);
    }
    final json = _decode(res);
    final raw = jMapList(json['races']);
    return Conditional(
      data: raw.map(Race.fromJson).toList(),
      etag: res.headers['etag'],
      raw: raw,
    );
  }

  Future<http.Response> _conditionalGet(
    String path,
    String token,
    String? etag,
  ) {
    final headers = _headers(token);
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
    return _guard(
      () => _client.get(Uri.parse('$kNuvoApiBase$path'), headers: headers),
    );
  }

  Future<List<PublicUser>> searchUsers(String token, String query) async {
    final uri = Uri.parse(
      '$kNuvoApiBase/users/search',
    ).replace(queryParameters: {'q': query});
    final res = await _guard(() => _client.get(uri, headers: _headers(token)));
    final json = _decode(res);
    return jMapList(json['users']).map(PublicUser.fromJson).toList();
  }

  Future<List<PublicUser>> getCrew(String token) async {
    final json = await _get('/crew', token);
    return jMapList(json['crew']).map(PublicUser.fromJson).toList();
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
    String? aiActivityType,
    String? activityId,
    String? metric,
    String? format,
    String? recurrence,
    String? targetUnit,
    String? proofMode,
    String? scoreDirection,
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
    if (aiActivityType != null) body['aiActivityType'] = aiActivityType;
    if (activityId != null) body['activityId'] = activityId;
    if (metric != null) body['metric'] = metric;
    if (format != null) body['format'] = format;
    if (recurrence != null) body['recurrence'] = recurrence;
    if (targetUnit != null) body['targetUnit'] = targetUnit;
    if (proofMode != null) body['proofMode'] = proofMode;
    if (scoreDirection != null) body['scoreDirection'] = scoreDirection;
    final json = await _post('/races', token, body);
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<Race> createCustomRace(
    String token, {
    required String title,
    int? targetValue,
    required String customActivityName,
    CustomPoseVerifierSpec? verifierSpec,
    TaughtMotionV2Spec? motionV2Spec,
    // Win condition. Anything but first_to_goal has no finish-line target —
    // a window / attempt race must never be sent a made-up one.
    String format = 'first_to_goal',
    String? finishLineAt,
    int? attemptDurationSeconds,
    int? attemptLimit,
    String? scoreDirection,
  }) async {
    final racesToTarget = format == 'first_to_goal';
    // The race verifies with the Motion V2 spec when one was learned — the
    // encoder matcher that self-validated the demos — falling back to the V1
    // sequence template only when V2 never produced a spec.
    final json = await _post('/races', token, {
      'title': title,
      'goalType': format,
      if (racesToTarget && targetValue != null) 'targetValue': targetValue,
      'unit': 'reps',
      'targetUnit': 'reps',
      'metric': 'reps',
      // Omitted for first_to_goal so that payload stays byte-identical to
      // what older workers already accept.
      if (!racesToTarget) 'format': format,
      if (!racesToTarget && finishLineAt != null && finishLineAt.isNotEmpty)
        'finishLineAt': finishLineAt,
      if (!racesToTarget && attemptDurationSeconds != null)
        'attemptDurationSeconds': attemptDurationSeconds,
      if (!racesToTarget && attemptLimit != null) 'attemptLimit': attemptLimit,
      if (!racesToTarget && scoreDirection == 'lower')
        'scoreDirection': 'lower',
      'proofRequirement': 'ai_check',
      'proofReviewMode': 'auto_accept',
      'proofMode': 'ai_check',
      'verificationMethod': 'ai',
      'verifierType': motionV2Spec != null
          ? motionV2VerifierType
          : customPoseVerifierType,
      'verifierVersion': motionV2Spec != null
          ? motionV2VerifierSpecVersion
          : customPoseVerifierSpecSchemaVersion,
      'customActivityName': customActivityName,
      'verifierSpec': motionV2Spec != null
          ? motionV2Spec.toJson()
          : verifierSpec!.toJson(),
    });
    return Race.fromJson(jMap(json['race']) ?? const {});
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
    if (aiActivityType != null) body['aiActivityType'] = aiActivityType;
    if (targetUnit != null) body['targetUnit'] = targetUnit;
    if (proofMode != null) body['proofMode'] = proofMode;
    final json = await _patch('/races/$id', token, body);
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<Conditional<Race>> getRaceDetail(
    String token,
    String id, {
    String? etag,
  }) async {
    final res = await _conditionalGet('/races/$id', token, etag);
    if (res.statusCode == 304) {
      return Conditional.notModified(etag: res.headers['etag'] ?? etag);
    }
    final json = _decode(res);
    final raw = jMap(json['race']) ?? const <String, dynamic>{};
    return Conditional(
      data: Race.fromJson(raw),
      etag: res.headers['etag'],
      raw: raw,
    );
  }

  Future<Race> submitProof(
    String token,
    String raceId, {
    String proofType = 'manual',
    String? note,
    required int value,
    String? mediaObjectKey,
  }) async {
    final body = <String, dynamic>{'proofType': proofType, 'value': value};
    if (note != null) body['note'] = note;
    if (mediaObjectKey != null) body['mediaObjectKey'] = mediaObjectKey;
    final json = await _post('/races/$raceId/proof', token, body);
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  /// Step 1 of proof evidence upload: a signed PUT URL + object key scoped to
  /// this race. The key is bound to the proof on submit (mediaObjectKey).
  Future<({String uploadUrl, String key})> requestProofMediaUploadUrl(
    String token,
    String raceId, {
    required String fileName,
    required String contentType,
  }) async {
    final json = await _post('/races/$raceId/proof-media/upload-url', token, {
      'fileName': fileName,
      'contentType': contentType,
    });
    return (uploadUrl: json['uploadUrl'] as String, key: json['key'] as String);
  }

  Future<Race> submitAiMotionProof(
    String token,
    String raceId, {
    required AiMotionResult result,
    required String clientSubmissionId,
    required String metric,
    String? verificationSessionId,
    ProofSessionResult? sessionResult,
  }) async {
    final json = await _post('/races/$raceId/proof', token, {
      ...result.toProofPayload(
        clientSubmissionId: clientSubmissionId,
        metric: metric,
        verificationSessionId: verificationSessionId,
      ),
      if (sessionResult != null) 'sessionResult': sessionResult.toJson(),
    });
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<Race> submitObjectCompositionProof(
    String token,
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
    String? verificationSessionId,
    ProofSessionResult? sessionResult,
  }) async {
    final json = await _post('/races/$raceId/proof', token, {
      'proofType': 'ai_motion',
      'clientSubmissionId': clientSubmissionId,
      if (verificationSessionId != null && verificationSessionId.isNotEmpty)
        'verificationSessionId': verificationSessionId,
      'activityType': activityId,
      'metric': metric,
      'value': value,
      'targetValue': targetValue,
      'detectedValue': value,
      'confidence': confidence,
      'verificationStatus': 'ai_verified',
      'verificationSummary': verificationSummary,
      'framesAnalyzed': framesAnalyzed,
      'validPoseFrames': framesAnalyzed,
      'durationMs': durationMs,
      'validatorVersion': validatorVersion,
      if (sessionResult != null) 'sessionResult': sessionResult.toJson(),
    });
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<Race> submitCustomPoseProof(
    String token,
    String raceId, {
    required CustomPoseRuntimeResult result,
    required String clientSubmissionId,
    String? verificationSessionId,
    ProofSessionResult? sessionResult,
  }) async {
    final json = await _post('/races/$raceId/proof', token, {
      ...result.toProofPayload(
        clientSubmissionId: clientSubmissionId,
        verificationSessionId: verificationSessionId,
      ),
      if (sessionResult != null) 'sessionResult': sessionResult.toJson(),
    });
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<Race> archiveRace(String token, String id) async {
    final json = await _post('/races/$id/archive', token, {});
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<Race> cancelRace(String token, String id) async {
    final json = await _post('/races/$id/cancel', token, {});
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<void> deleteRace(String token, String id) async {
    await _delete('/races/$id', token);
  }

  Future<void> leaveRace(String token, String id) async {
    await _post('/races/$id/leave', token, {});
  }

  Future<Race> joinRace(String token, String id) async {
    final json = await _post('/races/$id/join', token, {});
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<Race> addRaceParticipant(
    String token,
    String raceId,
    String userId,
  ) async {
    final json = await _post('/races/$raceId/participants', token, {
      'userId': userId,
    });
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  Future<String> createInviteCode(String token, String id) async {
    final json = await _post('/races/$id/invite-code', token, {});
    return jStr(json['inviteCode']) ?? '';
  }

  Future<Race> joinRaceByCode(String token, String code) async {
    final json = await _post('/races/join-code', token, {'code': code});
    return Race.fromJson(jMap(json['race']) ?? const {});
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
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  /// Community veto — dispute whether this proof should count in this race.
  /// Server-authoritative: returns the consensus outcome it computed.
  Future<ProofVetoResult> vetoProof(
    String token,
    String raceId,
    String proofId, {
    required String reason,
  }) async {
    final json = await _post('/races/$raceId/proofs/$proofId/veto', token, {
      'reason': reason,
    });
    return ProofVetoResult.fromJson(json);
  }

  /// Open a server-timestamped attempt for a best-attempt / timed race.
  /// The attempt binds to the next verified proof submission. Pass a stable
  /// [clientAttemptId] to make retries idempotent.
  Future<RaceAttemptResult> startAttempt(
    String token,
    String raceId, {
    String? clientAttemptId,
  }) async {
    final json = await _post('/races/$raceId/attempts', token, {
      'clientAttemptId': ?clientAttemptId,
    });
    return RaceAttemptResult.fromJson(json);
  }

  /// One-step rematch — the server clones participants + settings into a new
  /// race and returns it ready to race.
  Future<Race> rematchRace(String token, String raceId) async {
    final json = await _post('/races/$raceId/rematch', token, {});
    return Race.fromJson(jMap(json['race']) ?? const {});
  }

  /// Compact live-state payload for polling screens — no proof history.
  /// Pass the last seen [version] to get a cheap `{unchanged: true}` reply.
  Future<RaceLiveState> getRaceLiveState(
    String token,
    String raceId, {
    int? version,
  }) async {
    final json = await _get(
      '/races/$raceId/live${version != null ? '?version=$version' : ''}',
      token,
    );
    return RaceLiveState.fromJson(json);
  }
}
