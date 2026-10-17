// Crew's social-activity transport + state (docs/agents/21-race-system-v2-
// design.md §18, docs/agents/15-crew-system-plan.md §3).
//
// The feed consumes canonical domain events — `race_events` for race
// activity (never reverse-engineered from notification rows) and, until a
// crew domain-event log exists, crew-lifecycle notification rows — both
// projected server-side by GET /crew/feed. Models live in
// crew_activity_models.dart.
import 'dart:async';
import 'package:nuvo/core/utils/json_safe.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/demo/presentation_demo.dart';
import '../../../core/cache/cache_store.dart';
import '../../../core/network/api_base.dart';
import '../../../core/network/conditional.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import '../../auth/presentation/auth_controller.dart';
import 'crew_activity_models.dart';

export 'crew_activity_models.dart';

const _timeout = Duration(seconds: 20);

class CrewActivityApi {
  CrewActivityApi({http.Client? client}) : _client = client ?? http.Client();
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
    final body =
        res.body.isEmpty ? const <String, dynamic>{} : jsonDecode(res.body);
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    if (res.statusCode >= 400) {
      throw ApiException(
          res.statusCode, jStr(map['error']) ?? 'Request failed');
    }
    return map;
  }

  Future<List<CrewActivityItem>> getFeed(String token,
          {int limit = 40, String? cursor}) async =>
      (await getFeedConditional(token, limit: limit, cursor: cursor)).data ??
      const [];

  /// Conditional GET /crew/feed. A 304 returns [Conditional.notModified];
  /// servers that send no ETag leave [Conditional.etag] null.
  Future<Conditional<List<CrewActivityItem>>> getFeedConditional(
    String token, {
    int limit = 40,
    String? cursor,
    String? etag,
  }) async {
    final uri = Uri.parse('$kNuvoApiBase/crew/feed').replace(queryParameters: {
      'limit': '$limit',
      'cursor': ?cursor,
    });
    final res = await _guard(() => _client.get(uri,
        headers: {..._headers(token), 'If-None-Match': ?etag}));
    if (res.statusCode == 304) return Conditional.notModified(etag: etag);
    final json = _decode(res);
    return Conditional(
      data: parseFeedItems(json),
      etag: res.headers['etag'],
      raw: json,
    );
  }

  Future<ReactionSummary> react(
    String token, {
    required String entityType,
    required String entityId,
    required String emoji,
  }) async {
    final res = await _guard(
      () => _client.post(
        Uri.parse('$kNuvoApiBase/reactions'),
        headers: _headers(token),
        body: jsonEncode(
            {'entityType': entityType, 'entityId': entityId, 'emoji': emoji}),
      ),
    );
    return _summary(_decode(res));
  }

  Future<ReactionSummary> unreact(
    String token, {
    required String entityType,
    required String entityId,
  }) async {
    final res = await _guard(
      () => _client.delete(
        Uri.parse('$kNuvoApiBase/reactions'),
        headers: _headers(token),
        body: jsonEncode({'entityType': entityType, 'entityId': entityId}),
      ),
    );
    return _summary(_decode(res));
  }

  ReactionSummary _summary(Map<String, dynamic> json) {
    final counts = <String, int>{};
    if (json['counts'] is Map) {
      for (final e in (json['counts'] as Map).entries) {
        final n = (e.value as num?)?.toInt() ?? 0;
        if (n > 0) counts[e.key.toString()] = n;
      }
    }
    return ReactionSummary(
      counts: counts,
      myReaction: jStr(json['myReaction']),
    );
  }
}

/// Parses a decoded GET /crew/feed body (also used to rehydrate the snapshot).
List<CrewActivityItem> parseFeedItems(Map<String, dynamic> json) =>
    jMapList(json['items']).map(CrewActivityItem.fromJson)
        .toList();

/// Optional capability: validator-aware feed reads (see CrewConditionalSource).
abstract interface class CrewActivityConditionalSource {
  Future<Conditional<List<CrewActivityItem>>> getFeedConditional({
    int limit,
    String? etag,
  });
}

/// Real repository: [CrewActivityRepository] plus conditional first-page read.
class CrewActivitySyncRepository extends CrewActivityRepository
    implements CrewActivityConditionalSource {
  CrewActivitySyncRepository(super.api, super.store, super.authApi);

  @override
  Future<Conditional<List<CrewActivityItem>>> getFeedConditional({
    int limit = 40,
    String? etag,
  }) =>
      _withRefresh((t) => _api.getFeedConditional(t, limit: limit, etag: etag));
}

/// Token injection + 401 refresh for the activity endpoints (mirrors
/// CrewRepository).
class CrewActivityRepository {
  CrewActivityRepository(this._api, this._store, this._authApi);

  final CrewActivityApi _api;
  final SecureTokenStore _store;
  final AuthApi _authApi;

  Future<List<CrewActivityItem>> getFeed({int limit = 40, String? cursor}) =>
      _withRefresh((t) => _api.getFeed(t, limit: limit, cursor: cursor));
  Future<ReactionSummary> react(CrewActivityItem item, String emoji) =>
      _withRefresh((t) => _api.react(t,
          entityType: item.entityType!,
          entityId: item.entityId!,
          emoji: emoji));
  Future<ReactionSummary> unreact(CrewActivityItem item) => _withRefresh(
      (t) => _api.unreact(t,
          entityType: item.entityType!, entityId: item.entityId!));

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

class CrewActivityState {
  const CrewActivityState({
    this.items = const [],
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.reactingItemIds = const {},
  });

  final List<CrewActivityItem> items;
  final bool loading;
  final bool refreshing;
  final String? error;

  /// Item ids with a reaction write in flight — the bar disables taps on
  /// them so a slow network can't double-fire.
  final Set<String> reactingItemIds;

  bool get hasData => items.isNotEmpty;

  CrewActivityState copyWith({
    List<CrewActivityItem>? items,
    bool? loading,
    bool? refreshing,
    String? error,
    Set<String>? reactingItemIds,
  }) =>
      CrewActivityState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        error: error,
        reactingItemIds: reactingItemIds ?? this.reactingItemIds,
      );
}

class CrewActivityController extends StateNotifier<CrewActivityState> {
  CrewActivityController(
    this._repo, {
    this.onSessionExpired,
    this.isPresentationDemo = _neverPresentationDemo,
    this.demoUserId = _noDemoUser,
    this.cache,
    this.accountId = _noAccount,
  }) : super(const CrewActivityState());

  /// Disk snapshot of the first page. Null disables hydration/persistence.
  final CacheStore? cache;
  final String? Function() accountId;
  static String? _noAccount() => null;
  static const _snapshotDomain = 'crew_feed';
  static const _snapshotMaxAge = Duration(days: 7);
  String? _etag;
  Future<void>? _hydration;

  final CrewActivityRepository _repo;
  final VoidCallback? onSessionExpired;
  final bool Function() isPresentationDemo;
  static bool _neverPresentationDemo() => false;

  /// The signed-in user's id while in presentation mode — fixtures build
  /// payloads that genuinely name the viewer (overtakes, For-you items).
  final String Function() demoUserId;
  static String _noDemoUser() => '';

  static const _cacheLifetime = Duration(minutes: 3);
  static const _staleWindow = Duration(seconds: 45);
  Future<void>? _loadInFlight;
  DateTime? _loadedAt;
  int _generation = 0;
  int _revision = 0;

  void revalidate() {
    final at = _loadedAt;
    if (at != null && DateTime.now().difference(at) < _staleWindow) return;
    load(force: true);
  }

  /// Account id usable for the disk snapshot, or null (no cache, demo, or an
  /// id that is not a safe path segment).
  String? _cacheAccount() {
    if (cache == null || isPresentationDemo()) return null;
    final id = accountId();
    return id != null && isValidCacheId(id) ? id : null;
  }

  Future<void> _hydrate() async {
    final generation = _generation;
    final account = _cacheAccount();
    if (account == null) return;
    try {
      final entry =
          await cache!.read(account, _snapshotDomain, maxAge: _snapshotMaxAge);
      final data = entry?.data;
      if (data is! Map<String, dynamic>) return;
      final items = parseFeedItems(data);
      // Discard if signed out / switched meanwhile, or a network result won.
      if (!mounted || generation != _generation || _loadedAt != null) return;
      if (state.hasData) return;
      _etag = entry!.etag;
      state = state.copyWith(items: items, loading: false, refreshing: false);
    } catch (_) {
      // A bad snapshot is just a cache miss.
    }
  }

  /// Reaction writes change what GET /crew/feed returns: drop the validator
  /// and the persisted first page so neither is replayed stale.
  void _invalidateSnapshot() {
    _etag = null;
    final account = _cacheAccount();
    if (account != null) {
      cache!.write(account, _snapshotDomain, null).catchError((_) {});
    }
  }

  void markStale() {
    _loadedAt = null;
    _revision++;
    _loadInFlight = null;
    if (mounted) load(force: true);
  }

  Future<void> load({bool force = true}) {
    final at = _loadedAt;
    if (!force &&
        at != null &&
        DateTime.now().difference(at) < _cacheLifetime) {
      return Future.value();
    }
    if (_loadInFlight case final request?) return request;
    final request = _fetch();
    _loadInFlight = request;
    request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
    return request;
  }

  Future<void> _fetch() async {
    final generation = _generation;
    if (!mounted) return;
    // Give the disk snapshot a brief head start so its etag can be sent, but
    // never let a slow or stalled read hold back the network.
    await Future.any([
      _hydration ??= _hydrate(),
      Future<void>.delayed(const Duration(milliseconds: 40)),
    ]);
    if (!mounted || generation != _generation) return;
    final revision = _revision;
    final account = _cacheAccount();
    state =
        state.copyWith(loading: !state.hasData, refreshing: state.hasData);
    try {
      final Conditional<List<CrewActivityItem>> fetched;
      if (isPresentationDemo()) {
        fetched = Conditional(
            data: PresentationDemoData.crewActivity(demoUserId()));
      } else if (_repo case final CrewActivityConditionalSource source) {
        fetched = await source.getFeedConditional(etag: _etag);
      } else {
        fetched = Conditional(data: await _repo.getFeed());
      }
      if (!mounted || generation != _generation || revision != _revision) {
        return;
      }
      _loadedAt = DateTime.now();
      if (fetched.notModified) {
        // Same page: keep state as is, no flicker.
        state = state.copyWith(loading: false, refreshing: false);
        return;
      }
      _etag = fetched.etag;
      state = state.copyWith(
          items: fetched.data, loading: false, refreshing: false);
      if (account != null && fetched.raw != null) {
        cache!
            .write(account, _snapshotDomain, fetched.raw, etag: fetched.etag)
            .catchError((_) {});
      }
    } catch (error) {
      if (!mounted || generation != _generation || revision != _revision) {
        return;
      }
      // A demo session must never surface a network error — if the session
      // resolved as presentation mode mid-flight (or the real request raced
      // a demo transition), fixtures win over the failure.
      if (isPresentationDemo()) {
        _loadedAt = DateTime.now();
        state = state.copyWith(
          items: PresentationDemoData.crewActivity(demoUserId()),
          loading: false,
          refreshing: false,
        );
        return;
      }
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: "Couldn't refresh your friends' activity.",
      );
      if (error is ApiException && error.statusCode == 401) {
        onSessionExpired?.call();
      }
    }
  }

  /// Optimistic reaction toggle: same emoji again removes it, a different
  /// emoji switches it. The server enforces one-reaction-per-user-per-entity.
  /// Returns true when the write landed; callers surface a snack on false.
  Future<bool> toggleReaction(CrewActivityItem item, String emoji) async {
    if (!item.isReactionable) return false;
    if (state.reactingItemIds.contains(item.id)) return false;
    final generation = _generation;
    final removing = item.myReaction == emoji;
    state = state.copyWith(
        reactingItemIds: {...state.reactingItemIds, item.id});
    final optimistic = _applyOptimistic(item, emoji, removing);
    try {
      final summary = isPresentationDemo()
          ? ReactionSummary(
              counts: optimistic.reactions, myReaction: optimistic.myReaction)
          : removing
              ? await _repo.unreact(item)
              : await _repo.react(item, emoji);
      if (!mounted || generation != _generation) return false;
      _invalidateSnapshot();
      _replaceItem(
          item.id,
          (i) => i.copyWith(
              reactions: summary.counts,
              myReaction: () => summary.myReaction));
      return true;
    } catch (error) {
      if (mounted && generation == _generation) {
        _replaceItem(item.id, (_) => item);
        if (error is ApiException && error.statusCode == 401) {
          onSessionExpired?.call();
        }
      }
      return false;
    } finally {
      if (mounted && generation == _generation) {
        state = state.copyWith(
            reactingItemIds: {...state.reactingItemIds}..remove(item.id));
      }
    }
  }

  CrewActivityItem _applyOptimistic(
      CrewActivityItem item, String emoji, bool removing) {
    final counts = {...item.reactions};
    if (removing) {
      final n = (counts[emoji] ?? 0) - 1;
      n <= 0 ? counts.remove(emoji) : counts[emoji] = n;
    } else {
      if (item.myReaction != null && item.myReaction != emoji) {
        final n = (counts[item.myReaction!] ?? 0) - 1;
        n <= 0 ? counts.remove(item.myReaction) : counts[item.myReaction!] = n;
      }
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final updated = item.copyWith(
        reactions: counts, myReaction: () => removing ? null : emoji);
    _replaceItem(item.id, (_) => updated);
    return updated;
  }

  void _replaceItem(String id, CrewActivityItem Function(CrewActivityItem) f) {
    state = state.copyWith(
        items: [for (final i in state.items) i.id == id ? f(i) : i]);
  }

  /// Resets in-memory state. [wipeAccountId] (set on sign-out/account switch)
  /// also deletes that account's disk cache.
  void clear({String? wipeAccountId}) {
    _generation++;
    _revision++;
    _loadInFlight = null;
    _loadedAt = null;
    _etag = null;
    _hydration = null;
    if (wipeAccountId != null && cache != null) {
      cache!.clearAccount(wipeAccountId).catchError((_) {});
    }
    if (mounted) state = const CrewActivityState();
  }
}

final _crewActivityApiProvider =
    Provider<CrewActivityApi>((_) => CrewActivityApi());

final crewActivityRepositoryProvider = Provider<CrewActivityRepository>(
  (ref) => CrewActivitySyncRepository(
    ref.watch(_crewActivityApiProvider),
    ref.watch(secureTokenStoreProvider),
    ref.watch(authApiProvider),
  ),
);

final crewActivityProvider =
    StateNotifierProvider<CrewActivityController, CrewActivityState>((ref) {
  final controller = CrewActivityController(
    ref.watch(crewActivityRepositoryProvider),
    isPresentationDemo: () =>
        isPresentationDemoUser(ref.read(authControllerProvider).user),
    demoUserId: () => ref.read(authControllerProvider).user?.id ?? '',
    cache: ref.watch(cacheStoreProvider),
    accountId: () => ref.read(authControllerProvider).user?.id,
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).sessionExpired(),
  );
  var demo = isPresentationDemoUser(ref.read(authControllerProvider).user);
  if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
    controller.load(force: false);
  }
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    if (prev?.user?.id != next.user?.id || prev?.status != next.status) {
      final prevId = prev?.user?.id;
      controller.clear(
        wipeAccountId:
            prevId != null && next.user?.id != prevId ? prevId : null,
      );
      demo = isPresentationDemoUser(next.user);
      if (next.status == AuthStatus.authenticated) {
        controller.load(force: false);
      }
    }
  });
  ref.listen<bool>(presentationModeEnabledProvider, (_, _) {
    final current =
        isPresentationDemoUser(ref.read(authControllerProvider).user);
    if (demo == current) return;
    demo = current;
    controller.clear();
    if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
      controller.load(force: true);
    }
  });
  return controller;
});
