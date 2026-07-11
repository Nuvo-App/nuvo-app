import 'dart:convert';
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

  Future<ArenaSnapshot> fetchArenaSnapshot(String token) async {
    final res = await _client.get(
      Uri.parse('$_kApiBase/arena'),
      headers: _headers(token),
    );
    debugPrint(
      '[ArenaApi] status=${res.statusCode} body=${res.body.length > 300 ? res.body.substring(0, 300) : res.body}',
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
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
