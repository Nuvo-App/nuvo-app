// Arena snapshot endpoint. Same rules as race_api.dart: every request has a
// 20 s hard timeout (a raw un-timed _client call hangs a stalled socket
// forever), transport errors map to ApiException, JSON decode tolerates
// non-JSON error bodies. See docs/agents/10-pitfalls-and-fixes.md §A1.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart';
import 'arena_models.dart';

const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);

class ArenaApi {
  ArenaApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  /// Fails fast instead of hanging a stalled socket indefinitely.
  static const _requestTimeout = Duration(seconds: 20);

  Future<ArenaSnapshot> fetchArenaSnapshot(String token) async {
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$_kApiBase/arena'), headers: _headers(token))
          .timeout(_requestTimeout);
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
    debugPrint(
      '[ArenaApi] status=${res.statusCode} body=${res.body.length > 300 ? res.body.substring(0, 300) : res.body}',
    );
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(res.body);
      json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      json = <String, dynamic>{};
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    final snapshot = json['snapshot'];
    if (snapshot == null) {
      throw const ApiException(200, 'Missing snapshot in response');
    }
    return ArenaSnapshot.fromJson(snapshot as Map<String, dynamic>);
  }
}
