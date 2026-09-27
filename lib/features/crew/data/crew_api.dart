import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart' show ApiException;
import '../../races/data/race_models.dart' show PublicUser;
import '../../../core/network/api_base.dart';

const _timeout = Duration(seconds: 20);

/// Connect result — public profile connects immediately, private goes pending.
enum ConnectOutcome { active, pending }

enum CrewConnectionStatus { none, connected, pendingOutgoing, pendingIncoming }

CrewConnectionStatus crewConnectionStatusFrom(String? raw) => switch (raw) {
      'connected' => CrewConnectionStatus.connected,
      'pending_outgoing' => CrewConnectionStatus.pendingOutgoing,
      'pending_incoming' => CrewConnectionStatus.pendingIncoming,
      _ => CrewConnectionStatus.none,
    };

class CrewSearchResult {
  const CrewSearchResult({
    required this.user,
    required this.connectionStatus,
    this.mutualCount = 0,
  });
  final PublicUser user;
  final CrewConnectionStatus connectionStatus;

  /// Crew members I share with this person — the "why suggested" context.
  final int mutualCount;
}

class CrewRequestPage {
  const CrewRequestPage({this.incoming = const [], this.outgoing = const []});
  final List<PublicUser> incoming;
  final List<PublicUser> outgoing;
}

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
    this.lastActiveAt,
    this.level,
  });

  final String id;
  final String displayName;
  final String initials;
  final CrewConnectionStatus connectionStatus;
  final String? username;
  final String? memberId;
  final String? profilePhotoUrl;
  final bool isPrivate;

  /// Real presence timestamp — only populated for connected people.
  final DateTime? lastActiveAt;

  /// Server-owned Nuvo Level — null when the viewer can't see this member's
  /// full profile.
  final int? level;

  factory PublicProfileCard.fromJson(Map<String, dynamic> j) => PublicProfileCard(
        id: j['id'] as String,
        displayName: j['displayName'] as String? ?? 'Nuvo member',
        initials: j['initials'] as String? ?? 'N',
        connectionStatus: crewConnectionStatusFrom(j['connectionStatus'] as String?),
        username: j['username'] as String?,
        memberId: j['memberId'] as String?,
        profilePhotoUrl: j['profilePhotoUrl'] as String?,
        isPrivate: j['isPrivate'] as bool? ?? false,
        lastActiveAt: DateTime.tryParse(j['lastActiveAt'] as String? ?? ''),
        level: j['level'] as int?,
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
      () => _client.get(Uri.parse('$kNuvoApiBase/crew'), headers: _headers(token)),
    );
    final json = _decode(res);
    return (json['crew'] as List<dynamic>? ?? [])
        .map((e) => PublicUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CrewRequestPage> getRequestPage(String token) async {
    final res = await _guard(
      () => _client.get(Uri.parse('$kNuvoApiBase/crew/requests'), headers: _headers(token)),
    );
    final json = _decode(res);
    List<PublicUser> users(String key) => (json[key] as List<dynamic>? ?? [])
        .map((e) => PublicUser.fromJson(e as Map<String, dynamic>)).toList();
    return CrewRequestPage(incoming: users('requests'), outgoing: users('outgoing'));
  }

  Future<List<CrewSearchResult>> search(String token, String query) async {
    final uri = Uri.parse('$kNuvoApiBase/users/search').replace(queryParameters: {'q': query});
    final res = await _guard(() => _client.get(uri, headers: _headers(token)));
    final json = _decode(res);
    return (json['users'] as List<dynamic>? ?? []).map((value) {
      final user = value as Map<String, dynamic>;
      return CrewSearchResult(
        user: PublicUser.fromJson(user),
        connectionStatus: crewConnectionStatusFrom(user['connectionStatus'] as String?),
        mutualCount: (user['mutualCount'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  Future<PublicProfileCard> getUser(String token, String userId) async {
    final res = await _guard(
      () => _client.get(Uri.parse('$kNuvoApiBase/users/$userId'), headers: _headers(token)),
    );
    final json = _decode(res);
    return PublicProfileCard.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<ConnectOutcome> add(String token, String userId) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase/crew/add'),
        headers: _headers(token),
        body: jsonEncode({'userId': userId}),
      ),
    );
    final json = _decode(res);
    return json['status'] == 'pending' ? ConnectOutcome.pending : ConnectOutcome.active;
  }

  Future<void> _postJson(String token, String path, Map<String, dynamic> body) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase$path'),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
    _decode(res);
  }

  Future<void> _delete(String token, String path) async {
    final res = await _guard(
      () => _client.delete(Uri.parse('$kNuvoApiBase$path'), headers: _headers(token)),
    );
    _decode(res);
  }

  Future<void> reportUser(String token, String userId, {String? reason}) =>
      _postJson(token, '/reports/users/$userId', {'reason': ?reason});

  Future<void> reportRace(String token, String raceId, {String? reason}) =>
      _postJson(token, '/reports/races/$raceId', {'reason': ?reason});

  Future<void> reportContent(String token, String contentId, {String? reason}) =>
      _postJson(token, '/reports/content/$contentId', {'reason': ?reason});

  Future<void> blockUser(String token, String userId) =>
      _postJson(token, '/reports/blocks/$userId', const {});

  Future<void> unblockUser(String token, String userId) =>
      _delete(token, '/reports/blocks/$userId');

  Future<void> acceptRequest(String token, String userId) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase/crew/requests/$userId/accept'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }

  Future<void> declineRequest(String token, String userId) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase/crew/requests/$userId/decline'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }

  Future<void> remove(String token, String userId) async {
    final res = await _guard(
      () => _client.delete(
        Uri.parse('$kNuvoApiBase/crew/$userId'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }
}
