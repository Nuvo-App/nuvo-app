import 'dart:async';
import 'package:nuvo/core/utils/json_safe.dart';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart' show ApiException;
import '../../races/data/race_models.dart' show PublicUser;
import '../../profile/data/progression_models.dart' show NuvoBadge;
import '../../../core/network/api_base.dart';
import '../../../core/network/conditional.dart';

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
  const CrewRequestPage({
    this.incoming = const [],
    this.outgoing = const [],
    this.mutuals = const {},
  });
  final List<PublicUser> incoming;
  final List<PublicUser> outgoing;

  /// W2 additive: mutual-friends context per requester id — the
  /// "Friends with X and Y" line on request cards. Empty on older workers.
  final Map<String, CrewRequestMutuals> mutuals;
}

/// Mutual-friends context for one friend-request row (W2 `mutualCount` /
/// `mutualNames` on `GET /crew/requests`).
class CrewRequestMutuals {
  const CrewRequestMutuals({this.count = 0, this.names = const []});
  final int count;
  final List<String> names;
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
    this.lastActiveAt,
    this.level,
    this.levelProgress,
    this.achievementsEarned,
    this.achievementsTotal,
    this.featured = const [],
    this.earned = const [],
    this.racesFinished,
    this.racesWon,
    this.racesWithYou,
    this.bio,
    this.favoriteMovementKey,
    this.friendsCount,
    this.mutual,
    this.versus,
    this.friendship,
    this.lockedAchievements = const [],
    this.muted = false,
    this.activityShared,
  });

  final String id;
  final String displayName;
  final String initials;
  final CrewConnectionStatus connectionStatus;
  final String? username;
  final String? memberId;
  final String? profilePhotoUrl;

  /// Real presence timestamp — only populated for connected people.
  final DateTime? lastActiveAt;

  /// Server-owned Nuvo Level — null when the viewer can't see this member's
  /// full profile.
  final int? level;

  /// 0..1 fill inside the current level — public viewers get the fraction,
  /// never absolute XP. Null when hidden.
  final double? levelProgress;

  /// Earned-achievement count — same visibility rule as level.
  final int? achievementsEarned;

  /// Total achievement definitions — for the "earned / total" line.
  final int? achievementsTotal;

  /// Featured achievements (icon + name) — compact social identity.
  final List<PublicFeaturedBadge> featured;

  /// Earned achievements — the public collection. Progress on locked
  /// achievements is self-only, so this list is earned-only by contract.
  final List<NuvoBadge> earned;

  /// Canonical racing stats — finished races and wins.
  final int? racesFinished;
  final int? racesWon;

  /// Head-to-head racing context between the viewer and this member.
  final PublicRacesWithYou? racesWithYou;

  /// v13 additive fields (migration 0048) — all null when the server or the
  /// target's visibility doesn't provide them; the UI hides on null.
  final String? bio;
  final String? favoriteMovementKey;
  final int? friendsCount;
  final PublicMutual? mutual;
  final PublicVersus? versus;
  final PublicFriendship? friendship;
  final List<PublicLockedAchievement> lockedAchievements;
  final bool muted;
  final bool? activityShared;

  factory PublicProfileCard.fromJson(
    Map<String, dynamic> j,
  ) => PublicProfileCard(
    id: (jStr(j['id']) ?? ''),
    displayName: jStr(j['displayName']) ?? 'Nuvo member',
    initials: jStr(j['initials']) ?? 'N',
    connectionStatus: crewConnectionStatusFrom(jStr(j['connectionStatus'])),
    username: jStr(j['username']),
    memberId: jStr(j['memberId']),
    profilePhotoUrl: jStr(j['profilePhotoUrl']),
    lastActiveAt: DateTime.tryParse(jStr(j['lastActiveAt']) ?? ''),
    level: jInt(j['level']),
    levelProgress: jDouble(j['levelProgress']),
    achievementsEarned: jInt(j['achievementsEarned']),
    achievementsTotal: jInt(j['achievementsTotal']),
    featured: (j['featuredAchievements'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PublicFeaturedBadge.fromJson)
        .toList(),
    earned: (j['earnedAchievements'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NuvoBadge.fromJson)
        .toList(),
    racesFinished: (j['raceStats'] as Map<String, dynamic>?)?['races'] as int?,
    racesWon: (j['raceStats'] as Map<String, dynamic>?)?['wins'] as int?,
    racesWithYou: j['racesWithYou'] is Map<String, dynamic>
        ? PublicRacesWithYou.fromJson(j['racesWithYou'] as Map<String, dynamic>)
        : null,
    bio: jStr(j['bio']),
    favoriteMovementKey: jStr(j['favoriteMovementKey']),
    friendsCount: jInt(j['friendsCount']),
    mutual: jMap(j['mutual']) != null
        ? PublicMutual.fromJson(jMap(j['mutual'])!)
        : null,
    versus: jMap(j['versus']) != null
        ? PublicVersus.fromJson(jMap(j['versus'])!)
        : null,
    friendship: jMap(j['friendship']) != null
        ? PublicFriendship.fromJson(jMap(j['friendship'])!)
        : null,
    lockedAchievements: jMapList(
      j['lockedAchievements'],
    ).map(PublicLockedAchievement.fromJson).toList(),
    muted: jBool(j['muted']) ?? false,
    activityShared: jBool(j['activityShared']),
  );
}

/// Mutual-friend context between the viewer and a profile — count plus up
/// to three preview cards for a face stack.
class PublicMutual {
  const PublicMutual({required this.count, this.preview = const []});

  final int count;
  final List<PublicUser> preview;

  factory PublicMutual.fromJson(Map<String, dynamic> j) => PublicMutual(
    count: jInt(j['count']) ?? 0,
    preview: jMapList(j['preview']).map(PublicUser.fromJson).toList(),
  );
}

/// One side of the "[Name] vs you" scoreboard — identical shape for the
/// viewer (`you`) and the profile owner (`them`).
class PublicVersusSide {
  const PublicVersusSide({
    required this.level,
    required this.wins,
    this.winRatePercent,
    this.bestStreakDays,
    this.proofsThisWeek,
  });

  final int level;
  final int wins;
  final int? winRatePercent;
  final int? bestStreakDays;
  final int? proofsThisWeek;

  factory PublicVersusSide.fromJson(Map<String, dynamic> j) => PublicVersusSide(
    level: jInt(j['level']) ?? 0,
    wins: jInt(j['wins']) ?? 0,
    winRatePercent: jDouble(j['winRatePercent'])?.round(),
    bestStreakDays: jInt(j['bestStreakDays']),
    proofsThisWeek: jInt(j['proofsThisWeek']),
  );
}

class PublicVersus {
  const PublicVersus({required this.you, required this.them});

  final PublicVersusSide you;
  final PublicVersusSide them;

  factory PublicVersus.fromJson(Map<String, dynamic> j) => PublicVersus(
    you: PublicVersusSide.fromJson(jMap(j['you']) ?? const {}),
    them: PublicVersusSide.fromJson(jMap(j['them']) ?? const {}),
  );
}

/// One friendship badge between the viewer and a connected friend.
class PublicFriendshipBadge {
  const PublicFriendshipBadge({
    required this.key,
    required this.name,
    required this.description,
    required this.earned,
    required this.progress,
    required this.threshold,
  });

  final String key;
  final String name;
  final String description;
  final bool earned;
  final int progress;
  final int threshold;

  factory PublicFriendshipBadge.fromJson(Map<String, dynamic> j) =>
      PublicFriendshipBadge(
        key: jStr(j['key']) ?? '',
        name: jStr(j['name']) ?? 'Badge',
        description: jStr(j['description']) ?? '',
        earned: jBool(j['earned']) ?? false,
        progress: jInt(j['progress']) ?? 0,
        threshold: jInt(j['threshold']) ?? 1,
      );
}

/// Friendship context with a connected person — when the link formed plus
/// the per-pair badge ladder.
class PublicFriendship {
  const PublicFriendship({this.connectedSince, this.badges = const []});

  final String? connectedSince;
  final List<PublicFriendshipBadge> badges;

  factory PublicFriendship.fromJson(Map<String, dynamic> j) => PublicFriendship(
    connectedSince: jStr(j['connectedSince']),
    badges: jMapList(j['badges']).map(PublicFriendshipBadge.fromJson).toList(),
  );
}

/// Catalog metadata for an achievement the profile owner hasn't earned —
/// name + icon + category only; their progress is never exposed.
class PublicLockedAchievement {
  const PublicLockedAchievement({
    required this.key,
    required this.name,
    this.iconKey,
    this.category,
  });

  final String key;
  final String name;
  final String? iconKey;
  final String? category;

  factory PublicLockedAchievement.fromJson(Map<String, dynamic> j) =>
      PublicLockedAchievement(
        key: jStr(j['key']) ?? '',
        name: jStr(j['name']) ?? 'Achievement',
        iconKey: jStr(j['iconKey']),
        category: jStr(j['category']),
      );
}

/// Shared finished races between the viewer and this member, derived from
/// canonical roster + winner history on the server.
class PublicRacesWithYou {
  const PublicRacesWithYou({
    required this.total,
    required this.viewerWins,
    required this.targetWins,
    this.recent = const [],
  });

  final int total;
  final int viewerWins;
  final int targetWins;
  final List<PublicSharedRace> recent;

  factory PublicRacesWithYou.fromJson(Map<String, dynamic> j) =>
      PublicRacesWithYou(
        total: jInt(j['total']) ?? 0,
        viewerWins: jInt(j['viewerWins']) ?? 0,
        targetWins: jInt(j['targetWins']) ?? 0,
        recent: (j['recent'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PublicSharedRace.fromJson)
            .toList(),
      );
}

class PublicSharedRace {
  const PublicSharedRace({
    required this.raceId,
    required this.title,
    this.winnerUserId,
  });

  final String raceId;
  final String title;
  final String? winnerUserId;

  factory PublicSharedRace.fromJson(Map<String, dynamic> j) => PublicSharedRace(
    raceId: jStr(j['raceId']) ?? '',
    title: jStr(j['title']) ?? 'Race',
    winnerUserId: jStr(j['winnerUserId']),
  );
}

/// Compact featured achievement on another member's public surfaces.
class PublicFeaturedBadge {
  const PublicFeaturedBadge({
    required this.unlockId,
    required this.key,
    required this.name,
    this.iconKey,
  });

  final String unlockId;
  final String key;
  final String name;
  final String? iconKey;

  factory PublicFeaturedBadge.fromJson(Map<String, dynamic> j) =>
      PublicFeaturedBadge(
        unlockId: (jStr(j['unlockId']) ?? ''),
        key: jStr(j['key']) ?? '',
        name: jStr(j['name']) ?? '',
        iconKey: jStr(j['iconKey']),
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
    final Object? body;
    try {
      body = res.body.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(res.body);
    } on FormatException {
      throw ApiException(res.statusCode, 'Something went wrong. Try again.');
    }
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        jStr(map['error']) ?? 'Request failed',
      );
    }
    return map;
  }

  /// Conditional GET /crew. A 304 returns [Conditional.notModified]; older
  /// servers send no ETag, in which case [Conditional.etag] is null.
  Future<Conditional<List<PublicUser>>> getCrew(
    String token, {
    String? etag,
  }) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/crew'),
        headers: {..._headers(token), 'If-None-Match': ?etag},
      ),
    );
    if (res.statusCode == 304) return Conditional.notModified(etag: etag);
    final json = _decode(res);
    final members = jMapList(json['crew']).map(PublicUser.fromJson).toList();
    return Conditional(data: members, etag: res.headers['etag'], raw: json);
  }

  Future<CrewRequestPage> getRequestPage(String token) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/crew/requests'),
        headers: _headers(token),
      ),
    );
    final json = _decode(res);
    List<PublicUser> users(String key) => (json[key] as List<dynamic>? ?? [])
        .map((e) => PublicUser.fromJson(e as Map<String, dynamic>)).toList();
    // W2 additive: each request row may carry mutualCount / mutualNames[].
    final mutuals = <String, CrewRequestMutuals>{};
    for (final key in const ['requests', 'outgoing']) {
      for (final e in (json[key] as List<dynamic>? ?? [])) {
        if (e is! Map<String, dynamic>) continue;
        final id = jStr(e['id']);
        if (id == null) continue;
        final names = <String>[
          for (final n in jList(e['mutualNames']))
            if (jStr(n) != null) jStr(n)!,
        ];
        final count = jInt(e['mutualCount']) ?? names.length;
        if (count > 0 || names.isNotEmpty) {
          mutuals[id] = CrewRequestMutuals(count: count, names: names);
        }
      }
    }
    return CrewRequestPage(
      incoming: users('requests'),
      outgoing: users('outgoing'),
      mutuals: mutuals,
    );
  }

  Future<List<CrewSearchResult>> search(String token, String query) async {
    final uri = Uri.parse(
      '$kNuvoApiBase/users/search',
    ).replace(queryParameters: {'q': query});
    final res = await _guard(() => _client.get(uri, headers: _headers(token)));
    final json = _decode(res);
    return (json['users'] as List<dynamic>? ?? []).map((value) {
      final user = value as Map<String, dynamic>;
      return CrewSearchResult(
        user: PublicUser.fromJson(user),
        connectionStatus: crewConnectionStatusFrom(
          jStr(user['connectionStatus']),
        ),
        mutualCount: jInt(user['mutualCount']) ?? 0,
      );
    }).toList();
  }

  Future<PublicProfileCard> getUser(String token, String userId) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/users/$userId'),
        headers: _headers(token),
      ),
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
    return json['status'] == 'pending'
        ? ConnectOutcome.pending
        : ConnectOutcome.active;
  }

  Future<void> _postJson(
    String token,
    String path,
    Map<String, dynamic> body,
  ) async {
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
      () => _client.delete(
        Uri.parse('$kNuvoApiBase$path'),
        headers: _headers(token),
      ),
    );
    _decode(res);
  }

  Future<void> reportUser(String token, String userId, {String? reason}) =>
      _postJson(token, '/reports/users/$userId', {'reason': ?reason});

  Future<void> reportRace(String token, String raceId, {String? reason}) =>
      _postJson(token, '/reports/races/$raceId', {'reason': ?reason});

  Future<void> reportContent(
    String token,
    String contentId, {
    String? reason,
  }) => _postJson(token, '/reports/content/$contentId', {'reason': ?reason});

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

  /// GET /users/:id/activity — another member's activity map. [shared] is
  /// false when they turned the map off; 404/403 surfaces as [ApiException]
  /// so the caller can hide the section.
  Future<PublicUserActivity> getUserActivity(
    String token,
    String userId,
  ) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/users/$userId/activity'),
        headers: _headers(token),
      ),
    );
    final json = _decode(res);
    final days = <String, int>{};
    for (final d in jMapList(json['days'])) {
      final date = jStr(d['date']);
      if (date == null) continue;
      days[date] = jInt(d['proofs']) ?? 0;
    }
    return PublicUserActivity(
      shared: jBool(json['shared']) ?? true,
      days: days,
    );
  }

  Future<void> muteUser(String token, String userId) =>
      _postJson(token, '/mutes/users/$userId', const {});

  Future<void> unmuteUser(String token, String userId) =>
      _delete(token, '/mutes/users/$userId');

  /// GET /reports/blocks — the viewer's blocked accounts, for Settings.
  Future<List<PublicUser>> getBlocked(String token) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/reports/blocks'),
        headers: _headers(token),
      ),
    );
    final json = _decode(res);
    return jMapList(json['blocked']).map(PublicUser.fromJson).toList();
  }
}

/// Another member's activity-map payload — [days] is verified-proof count
/// per date; [shared] false means the owner turned the map off.
class PublicUserActivity {
  const PublicUserActivity({required this.shared, required this.days});

  final bool shared;
  final Map<String, int> days;
}
