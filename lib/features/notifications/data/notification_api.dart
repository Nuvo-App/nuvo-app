import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart' show ApiException;
import 'notification_models.dart';
import '../../../core/network/api_base.dart';

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

  /// [etag] is only meaningful for the first page (no cursor); a 304 returns
  /// [NotificationPage.notModified].
  Future<NotificationPage> list(String token, {String? cursor, String? etag}) async {
    final uri = Uri.parse('$kNuvoApiBase/notifications').replace(
      queryParameters: {'cursor': ?cursor},
    );
    final headers = _headers(token);
    if (etag != null && cursor == null) headers['If-None-Match'] = etag;
    final res = await _guard(() => _client.get(uri, headers: headers));
    final responseEtag = res.headers['etag'];
    if (res.statusCode == 304) {
      return NotificationPage.notModified(etag: responseEtag ?? etag);
    }
    return NotificationPage.fromJson(_decode(res), etag: responseEtag);
  }

  Future<void> markRead(String token, String id) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase/notifications/$id/read'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }

  Future<void> markAllRead(String token) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase/notifications/read-all'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }
}
