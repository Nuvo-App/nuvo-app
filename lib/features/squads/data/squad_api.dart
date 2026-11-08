import 'dart:async';
import 'package:nuvo/core/utils/json_safe.dart';
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
    this.ownerName,
    this.colorKey,
    this.iconKey,
    this.bio,
    this.createdAt,
    this.myRankWeek,
    this.memberPreviews = const [],
    this.nextRecurring,
    this.stats,
    this.muted = false,
  });

  final String id;
  final String name;
  final String joinCode;
  final bool isOwner;
  final int memberCount;
  final int raceCount;

  /// 'owner' | 'admin' | 'member' (detail only; null on list rows).
  final String? myRole;

  // ── W2 additive fields ──────────────────────────────────────────────
  // All optional; absent fields mean the caller hides the element.

  final String? ownerName;
  final String? colorKey;
  final String? iconKey;
  final String? bio;
  final DateTime? createdAt;

  /// My leaderboard rank this week inside the crew (e.g. "#2 this week").
  final int? myRankWeek;

  /// Face previews for the members strip ([] when absent).
  final List<CrewMemberPreview> memberPreviews;

  /// Next recurring race (e.g. "Pushups · In 2 days").
  final CrewRecurringRace? nextRecurring;

  /// Crew wins / races / streak counters (detail payload).
  final CrewGroupStats? stats;

  /// Whether I muted this crew's notifications (W2 `squad_members.muted_at`).
  final bool muted;

  /// Owners and admins run the crew: add races, remove members.
  bool get canManage => isOwner || myRole == 'admin' || myRole == 'owner';

  factory CrewGroup.fromJson(Map<String, dynamic> j) => CrewGroup(
        id: (jStr(j['id']) ?? ''),
        name: jStr(j['name']) ?? 'Crew',
        joinCode: jStr(j['joinCode']) ?? '',
        isOwner: jBool(j['isOwner']) ?? false,
        memberCount: jInt(j['memberCount']) ?? 0,
        raceCount: jInt(j['raceCount']) ?? 0,
        myRole: jStr(j['myRole']),
        ownerName: jStr(j['ownerName']),
        colorKey: jStr(j['colorKey']),
        iconKey: jStr(j['iconKey']),
        bio: jStr(j['bio']),
        createdAt: DateTime.tryParse(jStr(j['createdAt']) ?? ''),
        myRankWeek: jInt(j['myRankWeek']),
        memberPreviews: jMapList(j['memberPreviews'])
            .map(CrewMemberPreview.fromJson)
            .toList(),
        nextRecurring: jMap(j['nextRecurring']) == null
            ? null
            : CrewRecurringRace.fromJson(jMap(j['nextRecurring'])!),
        stats: jMap(j['stats']) == null
            ? null
            : CrewGroupStats.fromJson(jMap(j['stats'])!),
        muted: jBool(j['muted']) ?? jBool(j['myMuted']) ?? false,
      );
}

/// Parses a `GET /squads` body (also the persisted snapshot shape).
List<CrewGroup> parseCrewGroupList(Object? raw) {
  final map = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
  return jMapList(map['squads'])
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
        id: (jStr(j['id']) ?? ''),
        title: jStr(j['title']) ?? 'Race',
        status: jStr(j['status']) ?? 'active',
        targetValue: jInt(j['targetValue']),
        targetUnit: jStr(j['targetUnit']),
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
        userId: (jStr(j['userId']) ?? ''),
        displayName: jStr(j['displayName']) ?? 'Nuvo member',
        role: jStr(j['role']) ?? 'member',
        username: jStr(j['username']),
        profilePhotoUrl: jStr(j['profilePhotoUrl']),
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
        userId: (jStr(j['userId']) ?? ''),
        displayName: jStr(j['displayName']) ?? 'Nuvo member',
        rank: jInt(j['rank']) ?? 0,
        points: jInt(j['points']) ?? 0,
        wins: jInt(j['wins']) ?? 0,
        races: jInt(j['races']) ?? 0,
        isYou: jBool(j['isYou']) ?? false,
        profilePhotoUrl: jStr(j['profilePhotoUrl']),
      );
}

/// A face-only member preview — W2 `memberPreviews`, join-request rows and
/// auto-join faces all use this same shape.
class CrewMemberPreview {
  const CrewMemberPreview({
    required this.userId,
    required this.displayName,
    this.username,
    this.profilePhotoUrl,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? profilePhotoUrl;

  factory CrewMemberPreview.fromJson(Map<String, dynamic> j) =>
      CrewMemberPreview(
        userId: (jStr(j['userId']) ?? ''),
        displayName: jStr(j['displayName']) ?? 'Nuvo member',
        username: jStr(j['username']),
        profilePhotoUrl: jStr(j['profilePhotoUrl']),
      );
}

/// Crew wins / races / streak counters (W2 `stats` on the detail payload).
/// Each field is independently nullable so absent counters hide.
class CrewGroupStats {
  const CrewGroupStats({this.wins, this.races, this.streakDays});

  final int? wins;
  final int? races;
  final int? streakDays;

  bool get isEmpty => wins == null && races == null && streakDays == null;

  factory CrewGroupStats.fromJson(Map<String, dynamic> j) => CrewGroupStats(
        wins: jInt(j['wins']),
        races: jInt(j['races']),
        streakDays: jInt(j['streakDays']) ?? jInt(j['streak']),
      );
}

/// A recurring crew race (W2 `squad_recurring_races`). Every display field is
/// nullable — rows hide whatever the payload does not carry.
class CrewRecurringRace {
  const CrewRecurringRace({
    required this.id,
    required this.title,
    this.weekday,
    this.schedule,
    this.targetValue,
    this.targetUnit,
    this.rule,
    this.iconKey,
    this.liveRaceId,
    this.nextRunAt,
    this.inDays,
    this.autoJoin,
    this.autoJoinFaces = const [],
  });

  final String id;
  final String title;

  /// ISO weekday 1=Mon … 7=Sun (nullable → schedule text hidden).
  final int? weekday;

  /// Server-composed schedule label (e.g. "Every Monday"); wins over weekday.
  final String? schedule;
  final int? targetValue;
  final String? targetUnit;

  /// Server-composed rule label (e.g. "First to 100"); wins over target fields.
  final String? rule;
  final String? iconKey;

  /// Set when a spawned race is live right now → the "Live now" tag.
  final String? liveRaceId;
  final DateTime? nextRunAt;

  /// Days until the next run, if the server composes it.
  final int? inDays;

  /// My auto-join opt-in (null = default on / unknown).
  final bool? autoJoin;

  /// Faces of members with auto-join on.
  final List<CrewMemberPreview> autoJoinFaces;

  bool get isLive => liveRaceId != null && liveRaceId!.isNotEmpty;

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  /// "Every Monday" — from the server label first, then the weekday int.
  String? get scheduleLabel {
    final s = schedule;
    if (s != null && s.trim().isNotEmpty) return s.trim();
    final w = weekday;
    if (w == null || w < 1 || w > 7) return null;
    return 'Every ${_weekdayNames[w - 1]}';
  }

  /// "First to 100" — from the server label first, then target fields.
  String? get ruleLabel {
    final r = rule;
    if (r != null && r.trim().isNotEmpty) return r.trim();
    final t = targetValue;
    if (t == null || t <= 0) return null;
    final unit = targetUnit;
    return 'First to $t${unit == null ? '' : ' $unit'}';
  }

  /// Days until the next run — server value first, then nextRunAt vs now.
  int? get daysUntil {
    if (inDays != null) return inDays;
    final at = nextRunAt;
    if (at == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final then = DateTime(at.year, at.month, at.day);
    final d = then.difference(today).inDays;
    return d < 0 ? null : d;
  }

  /// "Live now" / "Today" / "Tomorrow" / "In 2 days"; null when unknown.
  String? get tagLabel {
    if (isLive) return 'Live now';
    final d = daysUntil;
    if (d == null) return null;
    if (d == 0) return 'Today';
    if (d == 1) return 'Tomorrow';
    return 'In $d days';
  }

  factory CrewRecurringRace.fromJson(Map<String, dynamic> j) =>
      CrewRecurringRace(
        id: (jStr(j['id']) ?? ''),
        title: jStr(j['title']) ?? jStr(j['name']) ?? 'Race',
        weekday: jInt(j['weekday']),
        schedule: jStr(j['schedule']),
        targetValue: jInt(j['targetValue']),
        targetUnit: jStr(j['targetUnit']) ?? jStr(j['unit']),
        rule: jStr(j['rule']) ?? jStr(j['targetLabel']),
        iconKey: jStr(j['iconKey']) ?? jStr(j['activityId']),
        liveRaceId: jStr(j['liveRaceId']),
        nextRunAt: DateTime.tryParse(jStr(j['nextRunAt']) ?? ''),
        inDays: jInt(j['inDays']) ?? jInt(j['daysUntil']),
        autoJoin: jBool(j['autoJoin']) ?? jBool(j['myAutoJoin']),
        autoJoinFaces: jMapList(j['autoJoinFaces'] ?? j['memberPreviews'])
            .map(CrewMemberPreview.fromJson)
            .toList(),
      );
}

/// An active crew-vs-crew battle (W2 `battle` on the detail payload). Rendered
/// only when present — there is no empty placeholder.
class CrewBattle {
  const CrewBattle({
    this.rivalId,
    this.rivalName,
    this.myPoints,
    this.rivalPoints,
    this.endsAt,
    this.status,
  });

  final String? rivalId;
  final String? rivalName;
  final int? myPoints;
  final int? rivalPoints;
  final DateTime? endsAt;

  /// 'active' renders; anything else (or null-with-points) is left to callers.
  final String? status;

  bool get isActive => status == null || status == 'active';

  factory CrewBattle.fromJson(Map<String, dynamic> j) => CrewBattle(
        rivalId: jStr(j['rivalId']) ?? jStr(j['rivalSquadId']),
        rivalName: jStr(j['rivalName']) ?? jStr(j['rival']),
        myPoints: jInt(j['myPoints'] ?? j['ourPoints']),
        rivalPoints: jInt(j['rivalPoints'] ?? j['theirPoints']),
        endsAt: DateTime.tryParse(jStr(j['endsAt']) ?? ''),
        status: jStr(j['status']),
      );
}

/// A "your friends' crews" row (W2 `GET /squads/discover`).
class CrewDiscoverItem {
  const CrewDiscoverItem({
    required this.id,
    required this.name,
    this.colorKey,
    this.iconKey,
    this.memberCount = 0,
    this.ownerName,
    this.memberPreviews = const [],
    this.requested = false,
  });

  final String id;
  final String name;
  final String? colorKey;
  final String? iconKey;
  final int memberCount;
  final String? ownerName;
  final List<CrewMemberPreview> memberPreviews;

  /// True when the row already carries a pending join request.
  final bool requested;

  factory CrewDiscoverItem.fromJson(Map<String, dynamic> j) =>
      CrewDiscoverItem(
        id: (jStr(j['id']) ?? ''),
        name: jStr(j['name']) ?? 'Crew',
        colorKey: jStr(j['colorKey']),
        iconKey: jStr(j['iconKey']),
        memberCount: jInt(j['memberCount']) ?? 0,
        ownerName: jStr(j['ownerName']),
        memberPreviews: jMapList(j['memberPreviews'])
            .map(CrewMemberPreview.fromJson)
            .toList(),
        requested: jStr(j['status']) == 'requested' ||
            jStr(j['joinStatus']) == 'requested' ||
            (jBool(j['requested']) ?? false),
      );
}

/// What a non-member sees of a crew (W2 `GET /squads/:id/preview`). Detail
/// 404s fall through to this so the crew page can still offer "Ask to join".
class CrewGroupPreview {
  const CrewGroupPreview({
    required this.id,
    required this.name,
    this.colorKey,
    this.iconKey,
    this.memberCount = 0,
    this.ownerName,
    this.bio,
    this.memberPreviews = const [],
    this.joinStatus,
  });

  final String id;
  final String name;
  final String? colorKey;
  final String? iconKey;
  final int memberCount;
  final String? ownerName;
  final String? bio;
  final List<CrewMemberPreview> memberPreviews;

  /// 'member' | 'requested' | null (not in it).
  final String? joinStatus;

  bool get isMember => joinStatus == 'member';
  bool get requested => joinStatus == 'requested';

  factory CrewGroupPreview.fromJson(Map<String, dynamic> j) {
    final squad = jMap(j['squad']) ?? j;
    return CrewGroupPreview(
      id: (jStr(squad['id']) ?? ''),
      name: jStr(squad['name']) ?? 'Crew',
      colorKey: jStr(squad['colorKey']),
      iconKey: jStr(squad['iconKey']),
      memberCount: jInt(squad['memberCount']) ?? 0,
      ownerName: jStr(squad['ownerName']),
      bio: jStr(squad['bio']),
      memberPreviews: jMapList(squad['memberPreviews'] ?? j['memberPreviews'])
          .map(CrewMemberPreview.fromJson)
          .toList(),
      joinStatus: jStr(j['joinStatus']) ?? jStr(squad['joinStatus']),
    );
  }
}

class CrewGroupDetail {
  const CrewGroupDetail({
    required this.group,
    required this.races,
    required this.standings,
    this.members = const [],
    this.recurring = const [],
    this.battle,
    this.joinRequests = const [],
  });

  final CrewGroup group;
  final List<CrewGroupRace> races;
  final List<CrewGroupStanding> standings;
  final List<CrewMember> members;

  /// Recurring races (W2; empty → section hidden).
  final List<CrewRecurringRace> recurring;

  /// Active crew-vs-crew battle (W2; null → hidden).
  final CrewBattle? battle;

  /// Pending join requests, owner/admin only (W2; empty → hidden).
  final List<CrewMemberPreview> joinRequests;

  factory CrewGroupDetail.fromJson(Map<String, dynamic> j) => CrewGroupDetail(
        group: CrewGroup.fromJson(jMap(j['squad']) ?? const {}),
        races: jMapList(j['races'])
            .map(CrewGroupRace.fromJson)
            .toList(),
        standings: jMapList(j['standings'])
            .map(CrewGroupStanding.fromJson)
            .toList(),
        members: jMapList(j['members'])
            .map(CrewMember.fromJson)
            .toList(),
        recurring: jMapList(j['recurring'])
            .map(CrewRecurringRace.fromJson)
            .toList(),
        battle: jMap(j['battle']) == null
            ? null
            : CrewBattle.fromJson(jMap(j['battle'])!),
        joinRequests: jMapList(j['joinRequests'])
            .map(CrewMemberPreview.fromJson)
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
      throw ApiException(res.statusCode, jStr(map['error']) ?? 'Request failed');
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

  /// Non-squads namespace (crew reports live under /reports).
  Uri _reportUri(String path) => Uri.parse('$kNuvoApiBase$path');

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
    return jInt(json['added']) ?? 0;
  }

  Future<void> leave(String token, String id) async {
    await _send(() => _client.post(_uri('/$id/leave'), headers: _headers(token)));
  }

  Future<void> deleteCrew(String token, String id) async {
    await _send(() => _client.delete(_uri('/$id'), headers: _headers(token)));
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

  // ── W2 additive endpoints ─────────────────────────────────────────────
  // Documented in docs/redesign/specs/CREW_SOCIAL.md §6. Until the W2 worker
  // lands each call 404s — callers catch ApiException and hide the feature.

  /// "Your friends' crews" (W2 `GET /squads/discover`).
  Future<List<CrewDiscoverItem>> discover(String token) async {
    final json = await _send(() => _client.get(
          _uri('/discover'),
          headers: _headers(token),
        ));
    return jMapList(json['squads'] ?? json['crews'])
        .map(CrewDiscoverItem.fromJson)
        .toList();
  }

  /// Non-member view (W2 `GET /squads/:id/preview`).
  Future<CrewGroupPreview> preview(String token, String id) async {
    final json = await _send(() => _client.get(
          _uri('/$id/preview'),
          headers: _headers(token),
        ));
    return CrewGroupPreview.fromJson(json);
  }

  /// Period-scoped standings (W2 `GET /squads/:id/standings?period=`).
  Future<List<CrewGroupStanding>> standings(
    String token,
    String id, {
    String period = 'all',
  }) async {
    final json = await _send(() => _client.get(
          _uri('/$id/standings?period=$period'),
          headers: _headers(token),
        ));
    return jMapList(json['standings'])
        .map(CrewGroupStanding.fromJson)
        .toList();
  }

  /// Ask to join a crew (W2 `POST /squads/:id/join-request`).
  Future<void> joinRequest(String token, String id) async {
    await _send(() => _client.post(
          _uri('/$id/join-request'),
          headers: _headers(token),
        ));
  }

  /// Owner/admin: approve a pending join request (W2).
  Future<void> approveJoinRequest(
    String token,
    String id,
    String userId,
  ) async {
    await _send(() => _client.post(
          _uri('/$id/join-requests/$userId/approve'),
          headers: _headers(token),
        ));
  }

  /// Owner/admin: decline a pending join request (W2).
  Future<void> declineJoinRequest(
    String token,
    String id,
    String userId,
  ) async {
    await _send(() => _client.post(
          _uri('/$id/join-requests/$userId/decline'),
          headers: _headers(token),
        ));
  }

  /// Mute / unmute a crew's notifications (W2 `POST /squads/:id/mute`).
  Future<void> setMuted(String token, String id, {required bool on}) async {
    await _send(() => _client.post(
          _uri('/$id/mute'),
          headers: _headers(token),
          body: jsonEncode({'on': on}),
        ));
  }

  /// Report a crew (W2 `POST /reports/squads/:id`).
  Future<void> reportCrew(String token, String id, {String? reason}) async {
    await _send(() => _client.post(
          _reportUri('/reports/squads/$id'),
          headers: _headers(token),
          body: jsonEncode({'reason': reason ?? 'crew'}),
        ));
  }

  /// Toggle my auto-join on a recurring race
  /// (W2 `POST /squads/:id/recurring/:rid/auto-join`).
  Future<void> setRecurringAutoJoin(
    String token,
    String id,
    String recurringId, {
    required bool on,
  }) async {
    await _send(() => _client.post(
          _uri('/$id/recurring/$recurringId/auto-join'),
          headers: _headers(token),
          body: jsonEncode({'on': on}),
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
  Future<void> deleteCrew(String id) =>
      _withRefresh((t) => _api.deleteCrew(t, id));
  Future<void> rename(String id, String name) =>
      _withRefresh((t) => _api.rename(t, id, name));
  Future<void> setRole(String id, String userId, String role) =>
      _withRefresh((t) => _api.setRole(t, id, userId, role));
  Future<void> removeMember(String id, String userId) =>
      _withRefresh((t) => _api.removeMember(t, id, userId));
  Future<void> removeRace(String id, String raceId) =>
      _withRefresh((t) => _api.removeRace(t, id, raceId));

  // ── W2 additive endpoints ─────────────────────────────────────────────

  Future<List<CrewDiscoverItem>> discover() => _withRefresh(_api.discover);
  Future<CrewGroupPreview> preview(String id) =>
      _withRefresh((t) => _api.preview(t, id));
  Future<List<CrewGroupStanding>> standings(String id, {String period = 'all'}) =>
      _withRefresh((t) => _api.standings(t, id, period: period));
  Future<void> joinRequest(String id) =>
      _withRefresh((t) => _api.joinRequest(t, id));
  Future<void> approveJoinRequest(String id, String userId) =>
      _withRefresh((t) => _api.approveJoinRequest(t, id, userId));
  Future<void> declineJoinRequest(String id, String userId) =>
      _withRefresh((t) => _api.declineJoinRequest(t, id, userId));
  Future<void> setMuted(String id, {required bool on}) =>
      _withRefresh((t) => _api.setMuted(t, id, on: on));
  Future<void> reportCrew(String id, {String? reason}) =>
      _withRefresh((t) => _api.reportCrew(t, id, reason: reason));
  Future<void> setRecurringAutoJoin(String id, String recurringId,
          {required bool on}) =>
      _withRefresh((t) => _api.setRecurringAutoJoin(t, id, recurringId, on: on));

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
