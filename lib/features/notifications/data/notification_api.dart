import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart' show ApiException;
import 'notification_models.dart';

const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);
const _timeout = Duration(seconds: 20);

class NotificationApi {
  NotificationApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<http.Response> _guard(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(408, 'The network timed out. Try again.');
    } on SocketException {
      throw const ApiException(0, "Can't reach Nuvo.");
    } on http.ClientException {
      throw const ApiException(0, "Can't reach Nuvo.");
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    final v = res.body.isEmpty ? const <String, dynamic>{} : jsonDecode(res.body);
    final map = v is Map<String, dynamic> ? v : const <String, dynamic>{};
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, map['error'] as String? ?? 'Request failed');
    }
    return map;
  }

  Future<NotificationPage> list(String token, {String? cursor}) async {
    final uri = Uri.parse('$_kApiBase/notifications').replace(
      queryParameters: {'cursor': ?cursor},
    );
    final res = await _guard(() => _client.get(uri, headers: _headers(token)));
    return NotificationPage.fromJson(_decode(res));
  }

  Future<void> markRead(String token, String id) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase/notifications/$id/read'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }

  Future<void> markAllRead(String token) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase/notifications/read-all'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }
}
