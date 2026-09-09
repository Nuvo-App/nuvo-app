import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart' show ApiException;
import '../../races/data/race_models.dart' show PublicUser;

const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);
const _timeout = Duration(seconds: 20);

/// Connect result — public profile connects immediately, private goes pending.
enum ConnectOutcome { active, pending }

enum CrewConnectionStatus { none, connected, pendingOutgoing, pendingIncoming }

CrewConnectionStatus _connFrom(String? raw) => switch (raw) {
      'connected' => CrewConnectionStatus.connected,
      'pending_outgoing' => CrewConnectionStatus.pendingOutgoing,
      'pending_incoming' => CrewConnectionStatus.pendingIncoming,
      _ => CrewConnectionStatus.none,
    };

class PublicProfileCard {
  const PublicProfileCard({
    required this.id,
    required this.displayName,
    required this.initials,
    required this.connectionStatus,
    this.username,
    this.memberId,
    this.profilePhotoUrl,
    this.isPrivate = false,
  });

  final String id;
  final String displayName;
  final String initials;
  final CrewConnectionStatus connectionStatus;
  final String? username;
  final String? memberId;
  final String? profilePhotoUrl;
  final bool isPrivate;

  factory PublicProfileCard.fromJson(Map<String, dynamic> j) => PublicProfileCard(
        id: j['id'] as String,
        displayName: j['displayName'] as String? ?? 'Nuvo member',
        initials: j['initials'] as String? ?? 'N',
        connectionStatus: _connFrom(j['connectionStatus'] as String?),
        username: j['username'] as String?,
        memberId: j['memberId'] as String?,
        profilePhotoUrl: j['profilePhotoUrl'] as String?,
        isPrivate: j['isPrivate'] as bool? ?? false,
      );
}

class CrewApi {
  CrewApi({http.Client? client}) : _client = client ?? http.Client();
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
      throw const ApiException(0, "Can't reach Nuvo. Check your connection.");
    } on http.ClientException {
      throw const ApiException(0, "Can't reach Nuvo. Check your connection.");
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = res.body.isEmpty ? const <String, dynamic>{} : jsonDecode(res.body);
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, map['error'] as String? ?? 'Request failed');
    }
    return map;
  }

  Future<List<PublicUser>> getCrew(String token) async {
    final res = await _guard(
      () => _client.get(Uri.parse('$_kApiBase/crew'), headers: _headers(token)),
    );
    final json = _decode(res);
    return (json['crew'] as List<dynamic>? ?? [])
        .map((e) => PublicUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PublicUser>> getRequests(String token) async {
    final res = await _guard(
      () => _client.get(Uri.parse('$_kApiBase/crew/requests'), headers: _headers(token)),
    );
    final json = _decode(res);
    return (json['requests'] as List<dynamic>? ?? [])
        .map((e) => PublicUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PublicProfileCard> getUser(String token, String userId) async {
    final res = await _guard(
      () => _client.get(Uri.parse('$_kApiBase/users/$userId'), headers: _headers(token)),
    );
    final json = _decode(res);
    return PublicProfileCard.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<ConnectOutcome> add(String token, String userId) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase/crew/add'),
        headers: _headers(token),
        body: jsonEncode({'userId': userId}),
      ),
    );
    final json = _decode(res);
    return json['status'] == 'pending' ? ConnectOutcome.pending : ConnectOutcome.active;
  }

  Future<void> acceptRequest(String token, String userId) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase/crew/requests/$userId/accept'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }

  Future<void> declineRequest(String token, String userId) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$_kApiBase/crew/requests/$userId/decline'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }

  Future<void> remove(String token, String userId) async {
    final res = await _guard(
      () => _client.delete(
        Uri.parse('$_kApiBase/crew/$userId'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }
}
