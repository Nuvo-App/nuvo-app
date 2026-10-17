import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_base.dart';
import '../../../core/network/conditional.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import '../../auth/presentation/auth_controller.dart';

const _timeout = Duration(seconds: 20);

/// A crew group — a named set of people who race together. The API calls it a
/// squad; the app always says "crew".
class CrewGroup {
  const CrewGroup({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.isOwner,
    required this.memberCount,
    required this.raceCount,
    this.myRole,
  });

  final String id;
  final String name;
  final String joinCode;
  final bool isOwner;
  final int memberCount;
  final int raceCount;

  /// 'owner' | 'admin' | 'member' (detail only; null on list rows).
  final String? myRole;

  /// Owners and admins run the crew: add races, remove members.
  bool get canManage => isOwner || myRole == 'admin' || myRole == 'owner';

  factory CrewGroup.fromJson(Map<String, dynamic> j) => CrewGroup(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Crew',
        joinCode: j['joinCode'] as String? ?? '',
        isOwner: j['isOwner'] as bool? ?? false,
        memberCount: j['memberCount'] as int? ?? 0,
        raceCount: j['raceCount'] as int? ?? 0,
        myRole: j['myRole'] as String?,
      );
}

/// Parses a `GET /squads` body (also the persisted snapshot shape).
List<CrewGroup> parseCrewGroupList(Object? raw) {
  final map = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
  return (map['squads'] as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()
      .map(CrewGroup.fromJson)
      .toList();
}

class CrewGroupRace {
  const CrewGroupRace({
    required this.id,
    required this.title,
    required this.status,
    this.targetValue,
    this.targetUnit,
  });

  final String id;
  final String title;
  final String status;
  final int? targetValue;
  final String? targetUnit;

  factory CrewGroupRace.fromJson(Map<String, dynamic> j) => CrewGroupRace(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Race',
        status: j['status'] as String? ?? 'active',
        targetValue: j['targetValue'] as int?,
        targetUnit: j['targetUnit'] as String?,
      );
}

/// One person in a crew, with the role that decides what they can do.
class CrewMember {
  const CrewMember({
    required this.userId,
    required this.displayName,
    required this.role,
    this.username,
    this.profilePhotoUrl,
  });

  final String userId;
  final String displayName;
  final String role; // owner | admin | member
  final String? username;
  final String? profilePhotoUrl;

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin';

  String get initials {
    final parts = displayName.replaceFirst('@', '').trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'N';
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.first[0].toUpperCase();
  }

  factory CrewMember.fromJson(Map<String, dynamic> j) => CrewMember(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String? ?? 'Nuvo member',
        role: j['role'] as String? ?? 'member',
        username: j['username'] as String?,
        profilePhotoUrl: j['profilePhotoUrl'] as String?,
      );
}

class CrewGroupStanding {
  const CrewGroupStanding({
    required this.userId,
    required this.displayName,
    required this.rank,
    required this.points,
    required this.wins,
    required this.races,
    required this.isYou,
    this.profilePhotoUrl,
  });

  final String userId;
  final String displayName;
  final int rank;
  final int points;
  final int wins;
  final int races;
  final bool isYou;
  final String? profilePhotoUrl;

  String get initials {
    final parts = displayName.replaceFirst('@', '').trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'N';
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.first[0].toUpperCase();
  }

  factory CrewGroupStanding.fromJson(Map<String, dynamic> j) =>
      CrewGroupStanding(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String? ?? 'Nuvo member',
        rank: j['rank'] as int? ?? 0,
        points: j['points'] as int? ?? 0,
        wins: j['wins'] as int? ?? 0,
        races: j['races'] as int? ?? 0,
        isYou: j['isYou'] as bool? ?? false,
        profilePhotoUrl: j['profilePhotoUrl'] as String?,
      );
}

class CrewGroupDetail {
  const CrewGroupDetail({
    required this.group,
    required this.races,
    required this.standings,
    this.members = const [],
  });

  final CrewGroup group;
  final List<CrewGroupRace> races;
  final List<CrewGroupStanding> standings;
  final List<CrewMember> members;

  factory CrewGroupDetail.fromJson(Map<String, dynamic> j) => CrewGroupDetail(
        group: CrewGroup.fromJson(j['squad'] as Map<String, dynamic>),
        races: (j['races'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CrewGroupRace.fromJson)
            .toList(),
        standings: (j['standings'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CrewGroupStanding.fromJson)
            .toList(),
        members: (j['members'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CrewMember.fromJson)
            .toList(),
      );
}

class SquadApi {
  SquadApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<http.Response> _raw(Future<http.Response> Function() send) async {
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

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() send,
  ) async => _decode(await _raw(send));

  /// Conditional GET: sends `If-None-Match` when [etag] is set; a 304 yields
  /// [Conditional.notModified]. Servers that send no ETag give `etag: null`.
  Future<Conditional<T>> _conditional<T>(
    String path,
    String token,
    String? etag,
    T Function(Map<String, dynamic> json) parse,
  ) async {
    final headers = _headers(token);
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
    final res = await _raw(() => _client.get(_uri(path), headers: headers));
    if (res.statusCode == 304) return Conditional.notModified(etag: etag);
    final json = _decode(res);
    return Conditional(
      data: parse(json),
      etag: res.headers['etag'],
      raw: json,
    );
  }

  Uri _uri(String path) => Uri.parse('$kNuvoApiBase/squads$path');

  Future<Conditional<List<CrewGroup>>> list(String token, {String? etag}) =>
      _conditional('', token, etag, parseCrewGroupList);

  Future<CrewGroup> create(String token, String name) async {
    final json = await _send(() => _client.post(
          _uri(''),
          headers: _headers(token),
          body: jsonEncode({'name': name}),
        ));
    return CrewGroup.fromJson(json['squad'] as Map<String, dynamic>);
  }

  Future<void> join(String token, String code) async {
    await _send(() => _client.post(
          _uri('/join'),
          headers: _headers(token),
          body: jsonEncode({'code': code}),
        ));
  }

  Future<Conditional<CrewGroupDetail>> detail(
    String token,
    String id, {
    String? etag,
  }) => _conditional('/$id', token, etag, CrewGroupDetail.fromJson);

  Future<int> addRace(String token, String id, String raceId) async {
    final json = await _send(() => _client.post(
          _uri('/$id/races'),
          headers: _headers(token),
          body: jsonEncode({'raceId': raceId}),
        ));
    return json['added'] as int? ?? 0;
  }

  Future<void> leave(String token, String id) async {
    await _send(() => _client.post(_uri('/$id/leave'), headers: _headers(token)));
  }

  Future<void> rename(String token, String id, String name) async {
    await _send(() => _client.patch(
          _uri('/$id'),
          headers: _headers(token),
          body: jsonEncode({'name': name}),
        ));
  }

  Future<void> setRole(String token, String id, String userId, String role) async {
    await _send(() => _client.post(
          _uri('/$id/members/$userId/role'),
          headers: _headers(token),
          body: jsonEncode({'role': role}),
        ));
  }

  Future<void> removeMember(String token, String id, String userId) async {
    await _send(() => _client.delete(
          _uri('/$id/members/$userId'),
          headers: _headers(token),
        ));
  }

  Future<void> removeRace(String token, String id, String raceId) async {
    await _send(() => _client.delete(
          _uri('/$id/races/$raceId'),
          headers: _headers(token),
        ));
  }
}

/// Token injection + 401 refresh (mirrors CrewRepository).
class SquadRepository {
  SquadRepository(this._api, this._store, this._authApi);

  final SquadApi _api;
  final SecureTokenStore _store;
  final AuthApi _authApi;

  Future<Conditional<List<CrewGroup>>> list({String? etag}) =>
      _withRefresh((t) => _api.list(t, etag: etag));
  Future<CrewGroup> create(String name) => _withRefresh((t) => _api.create(t, name));
  Future<void> join(String code) => _withRefresh((t) => _api.join(t, code));
  Future<Conditional<CrewGroupDetail>> detail(String id, {String? etag}) =>
      _withRefresh((t) => _api.detail(t, id, etag: etag));
  Future<int> addRace(String id, String raceId) =>
      _withRefresh((t) => _api.addRace(t, id, raceId));
  Future<void> leave(String id) => _withRefresh((t) => _api.leave(t, id));
  Future<void> rename(String id, String name) =>
      _withRefresh((t) => _api.rename(t, id, name));
  Future<void> setRole(String id, String userId, String role) =>
      _withRefresh((t) => _api.setRole(t, id, userId, role));
  Future<void> removeMember(String id, String userId) =>
      _withRefresh((t) => _api.removeMember(t, id, userId));
  Future<void> removeRace(String id, String raceId) =>
      _withRefresh((t) => _api.removeRace(t, id, raceId));

  Future<T> _withRefresh<T>(Future<T> Function(String token) call) async {
    final token = await _store.getAccessToken();
    if (token == null) throw const ApiException(401, 'Not authenticated');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      if (await _store.getAccessToken() != token) {
        throw const ApiException(409, 'Your account changed. Try again.');
      }
      final refresh = await _store.getRefreshToken();
      if (refresh == null) rethrow;
      final fresh = await _authApi.refreshSession(refresh);
      if (await _store.getRefreshToken() != refresh) {
        throw const ApiException(409, 'Your account changed. Try again.');
      }
      final currentToken = await _store.getAccessToken();
      if (currentToken != token) {
        if (currentToken == null) {
          throw const ApiException(409, 'Your account changed. Try again.');
        }
        return await call(currentToken);
      }
      await _store.saveAccessToken(fresh);
      return await call(fresh);
    }
  }
}

final squadRepositoryProvider = Provider<SquadRepository>(
  (ref) => SquadRepository(
    SquadApi(),
    ref.watch(secureTokenStoreProvider),
    ref.watch(authApiProvider),
  ),
);
