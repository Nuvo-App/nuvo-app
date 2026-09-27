import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_base.dart';
import '../../auth/data/auth_api.dart';
import 'progression_models.dart';

/// Thin client for /progression — XP, levels, unlocks, badges. All truth is
/// server-side; this client only transports payloads.
class ProgressionApi {
  ProgressionApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _requestTimeout = Duration(seconds: 20);

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

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
      () => _client.get(Uri.parse('$kNuvoApiBase$path'), headers: _headers(token)),
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

  Future<Map<String, dynamic>> _put(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    final res = await _guard(
      () => _client.put(
        Uri.parse('$kNuvoApiBase$path'),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
    return _decode(res);
  }

  Future<NuvoProgression> getProgression(String token) async {
    final json = await _get('/progression', token);
    return NuvoProgression.fromJson(
      (json['progression'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Future<List<NuvoBadge>> getBadges(String token) async {
    final json = await _get('/progression/badges', token);
    return (json['badges'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NuvoBadge.fromJson)
        .toList();
  }

  Future<List<NuvoBadge>> setFeatured(String token, List<String> unlockIds) async {
    final json = await _put('/progression/featured', token, {'unlockIds': unlockIds});
    return (json['badges'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NuvoBadge.fromJson)
        .toList();
  }

  Future<NuvoProgression> markLevelSeen(String token) async {
    final json = await _post('/progression/level-seen', token, const {});
    return NuvoProgression.fromJson(
      (json['progression'] as Map<String, dynamic>?) ?? const {},
    );
  }

  /// What one race paid out — the finish screen's XP breakdown.
  Future<NuvoRaceXp> getRaceXp(String token, String raceId) async {
    final json = await _get('/progression/race/$raceId', token);
    return NuvoRaceXp.fromJson(
      (json['xp'] as Map<String, dynamic>?) ?? const {},
    );
  }
}
