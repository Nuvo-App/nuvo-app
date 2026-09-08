// HTTP for the unified invite endpoints. Preview is public (works logged-out);
// mint / accept / revoke require a bearer token. Every request has a hard
// timeout — a stalled socket must surface as an ApiException, never hang.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart' show ApiException;
import 'invite_models.dart';

const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);

const _timeout = Duration(seconds: 20);

class InviteApi {
  InviteApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<http.Response> _guard(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(408, 'The network timed out. Try again.');
    } on SocketException {
      throw const ApiException(0, "Can't reach Nuvo. Check your connection.");
    } on http.ClientException {
      throw const ApiException(0, "Can't reach Nuvo. Check your connection.");
    }
  }

  Map<String, dynamic> _json(http.Response res) {
    if (res.body.isEmpty) return {};
    final v = jsonDecode(res.body);
    return v is Map<String, dynamic> ? v : {};
  }

  /// Preview — never throws on 404/410; the body's `status` carries the reason.
  Future<InvitePreview> preview(String token, {String? authToken}) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse('$_kApiBase/invites/$token'),
        headers: _headers(authToken),
      ),
    );
    if (res.statusCode >= 500) {
      throw ApiException(res.statusCode, 'Something went wrong loading this invite.');
    }
    return InvitePreview.fromJson(_json(res));
  }

  /// Accept — auth required. Idempotent server-side.
  Future<InviteAcceptResult> accept(String token, String authToken) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase/invites/$token/accept'),
        headers: _headers(authToken),
      ),
    );
    if (res.statusCode == 401) throw const ApiException(401, 'Not authenticated');
    if (res.statusCode >= 500) {
      throw ApiException(res.statusCode, "Couldn't accept this invite. Try again.");
    }
    final json = _json(res);
    if (res.statusCode == 403 && json['error'] != null) {
      throw ApiException(403, json['error'] as String);
    }
    return InviteAcceptResult.fromJson(json);
  }

  /// Mint a shareable token for an entity the caller controls.
  Future<MintedInvite> mint(
    String authToken, {
    required String kind,
    String? targetId,
    int? maxUses,
    int? expiresInSeconds,
  }) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase/invites'),
        headers: _headers(authToken),
        body: jsonEncode(<String, dynamic>{
          'kind': kind,
          'targetId': ?targetId,
          'maxUses': ?maxUses,
          'expiresInSeconds': ?expiresInSeconds,
        }),
      ),
    );
    final json = _json(res);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, json['error'] as String? ?? 'Could not create invite');
    }
    return MintedInvite.fromJson(json);
  }

  Future<void> revoke(String token, String authToken) async {
    final res = await _guard(
      () => _client.delete(
        Uri.parse('$_kApiBase/invites/$token'),
        headers: _headers(authToken),
      ),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Could not revoke this invite');
    }
  }
}
