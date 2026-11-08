import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_base.dart';
import '../../../core/utils/json_safe.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import '../../auth/presentation/auth_controller.dart';

/// Own-profile payload from GET /profile/me — only the v13 preference fields
/// (migration 0048) that auth's user model doesn't carry. Presence flags tell
/// the UI whether the server actually returned each key; absent keys mean an
/// older Worker and the related controls must hide, never fake.
class NuvoProfilePrefs {
  const NuvoProfilePrefs({
    required this.hasBio,
    required this.hasFavoriteMovement,
    required this.hasActivityMapShared,
    required this.hasRaceInvitesFrom,
    this.bio,
    this.favoriteMovementKey,
    this.activityMapShared,
    this.raceInvitesFrom,
  });

  final bool hasBio;
  final bool hasFavoriteMovement;
  final bool hasActivityMapShared;
  final bool hasRaceInvitesFrom;
  final String? bio;
  final String? favoriteMovementKey;
  final bool? activityMapShared;

  /// 'everyone' | 'friends' — who may add this member to a race.
  final String? raceInvitesFrom;

  factory NuvoProfilePrefs.fromJson(Map<String, dynamic> j) => NuvoProfilePrefs(
    hasBio: j.containsKey('bio'),
    hasFavoriteMovement: j.containsKey('favoriteMovementKey'),
    hasActivityMapShared: j.containsKey('activityMapShared'),
    hasRaceInvitesFrom: j.containsKey('raceInvitesFrom'),
    bio: jStr(j['bio']),
    favoriteMovementKey: jStr(j['favoriteMovementKey']),
    activityMapShared: jBool(j['activityMapShared']),
    raceInvitesFrom: jStr(j['raceInvitesFrom']),
  );

  NuvoProfilePrefs copyWith({
    String? bio,
    String? favoriteMovementKey,
    bool? activityMapShared,
    String? raceInvitesFrom,
  }) => NuvoProfilePrefs(
    hasBio: hasBio,
    hasFavoriteMovement: hasFavoriteMovement,
    hasActivityMapShared: hasActivityMapShared,
    hasRaceInvitesFrom: hasRaceInvitesFrom,
    bio: bio ?? this.bio,
    favoriteMovementKey: favoriteMovementKey ?? this.favoriteMovementKey,
    activityMapShared: activityMapShared ?? this.activityMapShared,
    raceInvitesFrom: raceInvitesFrom ?? this.raceInvitesFrom,
  );

  bool get hasV13Prefs =>
      hasBio ||
      hasFavoriteMovement ||
      hasActivityMapShared ||
      hasRaceInvitesFrom;
}

/// Client for GET /profile/me plus the POST /profile preference fields auth's
/// saveProfile doesn't cover (bio, favorite movement, activity-map sharing,
/// race invites). Mirrors [CrewRepository]'s one-retry token refresh.
class ProfileV13Api {
  ProfileV13Api(this._store, this._authApi, {http.Client? client})
    : _client = client ?? http.Client();

  final SecureTokenStore _store;
  final AuthApi _authApi;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

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

  Future<T> _withRefresh<T>(Future<T> Function(String token) call) async {
    final token = await _store.getAccessToken();
    if (token == null) throw const ApiException(401, 'Not authenticated');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      // Never refresh an old request into a newly signed-in account.
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

  /// GET /profile/me → the v13 preference strip. [NuvoProfilePrefs.has*]
  /// flags mark which keys the server returned.
  Future<NuvoProfilePrefs> getPrefs() => _withRefresh((t) async {
    final res = await _guard(
      () => _client.get(
        Uri.parse('$kNuvoApiBase/profile/me'),
        headers: _headers(t),
      ),
    );
    return NuvoProfilePrefs.fromJson(_decode(res));
  });

  /// POST /profile — partial update; the server only touches supplied fields.
  Future<void> updatePrefs({
    String? bio,
    bool clearBio = false,
    String? favoriteMovementKey,
    bool clearFavoriteMovement = false,
    bool? activityMapShared,
    String? raceInvitesFrom,
  }) => _withRefresh((t) async {
    final body = <String, dynamic>{
      if (clearBio) 'bio': null else if (bio != null) 'bio': bio,
      if (clearFavoriteMovement)
        'favoriteMovementKey': null
      else if (favoriteMovementKey != null)
        'favoriteMovementKey': favoriteMovementKey,
      if (activityMapShared != null) 'activityMapShared': activityMapShared,
      if (raceInvitesFrom != null) 'raceInvitesFrom': raceInvitesFrom,
    };
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase/profile'),
        headers: _headers(t),
        body: jsonEncode(body),
      ),
    );
    _decode(res);
  });
}

final profileV13ApiProvider = Provider<ProfileV13Api>(
  (ref) => ProfileV13Api(
    ref.watch(secureTokenStoreProvider),
    ref.watch(authApiProvider),
  ),
);

/// Own v13 preference strip — bio, favorite movement, activity-map sharing,
/// race-invite scope. Failure is non-fatal: the prefs-driven rows hide.
final profilePrefsProvider = FutureProvider.autoDispose<NuvoProfilePrefs>((
  ref,
) async {
  return ref.watch(profileV13ApiProvider).getPrefs();
});
