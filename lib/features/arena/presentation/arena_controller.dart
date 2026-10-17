// Arena next-move snapshot state. Same shape and rules as RaceController
// (docs/agents/08 provider graph, docs/agents/10 §A1): StateNotifierProvider is
// not recreated on sign-out, so clearSnapshot() must null the cache timestamp
// AND the in-flight future or a hung load wedges the tab until an app kill.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/cache/cache_store.dart';
import '../../../core/demo/presentation_demo.dart';
import '../../../core/network/conditional.dart';
import '../data/arena_api.dart';
import '../data/arena_models.dart';
import '../data/arena_repository.dart';

class ArenaState {
  const ArenaState({
    this.snapshot,
    this.loading = false,
    this.refreshing = false,
    this.error,
  });

  final ArenaSnapshot? snapshot;

  /// First load, nothing cached — a full skeleton is fine.
  final bool loading;

  /// Background revalidation with a snapshot already on screen — keep it.
  final bool refreshing;

  final String? error;

  bool get hasData => snapshot != null;

  ArenaState copyWith({
    ArenaSnapshot? snapshot,
    bool? loading,
    bool? refreshing,
    String? error,
  }) => ArenaState(
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: error,
  );
}

class ArenaController extends StateNotifier<ArenaState> {
  ArenaController(
    this._repo, {
    this.onSessionExpired,
    this.isPresentationDemo = _neverPresentationDemo,
    this.presentationUserId = _emptyPresentationUserId,
    this.cache,
    this.accountId = _noAccountId,
  }) : super(const ArenaState());

  final CacheStore? cache;

  /// Signed-in user id, or null. Used only as the disk-cache account key.
  final String? Function() accountId;
  static String? _noAccountId() => null;
  static const _cacheDomain = 'arena';
  static const _cacheMaxAge = Duration(days: 7);

  /// ETag of the last 200 snapshot, sent as If-None-Match on revalidate.
  String? _etag;

  /// Account whose snapshot this controller last read/wrote on disk; wiped on
  /// sign-out.
  String? _activeAccount;

  String? _cacheAccount() {
    final id = accountId();
    if (cache == null || id == null || !isValidCacheId(id)) return null;
    if (isPresentationDemo()) return null;
    return id;
  }

  /// Show the last on-disk snapshot immediately (as `refreshing`), restoring
  /// its ETag. Never blocks the first frame: callers do not await it before
  /// rendering. A result that lands after sign-out is discarded.
  Future<void> hydrate() async {
    final id = _cacheAccount();
    if (id == null) return;
    final generation = _generation;
    final entry = await cache!.read(id, _cacheDomain, maxAge: _cacheMaxAge);
    if (entry == null ||
        !mounted ||
        generation != _generation ||
        state.hasData ||
        accountId() != id) {
      return;
    }
    final ArenaSnapshot snapshot;
    try {
      snapshot = ArenaSnapshot.fromJson(
        Map<String, dynamic>.from(entry.data as Map),
      );
    } catch (_) {
      return;
    }
    _activeAccount = id;
    _etag = entry.etag;
    state = ArenaState(snapshot: snapshot, refreshing: true);
  }

  final ArenaRepository _repo;
  final VoidCallback? onSessionExpired;
  final bool Function() isPresentationDemo;
  final String Function() presentationUserId;

  static bool _neverPresentationDemo() => false;
  static String _emptyPresentationUserId() => '';
  static const _cacheLifetime = Duration(minutes: 5);
  static const _staleWindow = Duration(seconds: 45);
  Future<void>? _loadInFlight;
  DateTime? _snapshotLoadedAt;

  /// Bumped by [clearSnapshot] (sign-out) — see the matching guard in
  /// RaceController._generation. Stops a fetch started before sign-out from
  /// landing after clearSnapshot() and resurrecting the previous account's
  /// snapshot into the new session.
  int _generation = 0;

  /// SWR entry point — screen focus / app resume. No-op if fresh, otherwise a
  /// background refresh while the current snapshot stays on screen.
  void revalidate() {
    final at = _snapshotLoadedAt;
    if (state.hasData &&
        at != null &&
        DateTime.now().difference(at) < _staleWindow) {
      return;
    }
    loadSnapshot(force: true);
  }

  /// A sibling cache (races) changed — the arena is derived from races.
  /// Lazy: only marks the snapshot stale; it fetches immediately only when a
  /// screen is watching, otherwise the next revalidate() picks it up.
  void markStale() {
    _snapshotLoadedAt = null;
    if (mounted && hasListeners) loadSnapshot(force: true);
  }

  Future<void> loadSnapshot({bool force = true}) {
    final loadedAt = _snapshotLoadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _cacheLifetime) {
      return Future.value();
    }
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;

    final request = _fetchSnapshot();
    _loadInFlight = request;
    request.then<void>(
      (_) => _clearInFlight(request),
      onError: (Object _, StackTrace _) => _clearInFlight(request),
    );
    return request;
  }

  void _clearInFlight(Future<void> request) {
    if (identical(_loadInFlight, request)) _loadInFlight = null;
  }

  Future<void> _fetchSnapshot() async {
    final generation = _generation;
    final account = _cacheAccount();
    if (mounted) {
      final haveData = state.hasData;
      if (state.loading != !haveData || state.refreshing != haveData) {
        state = ArenaState(
          snapshot: state.snapshot,
          loading: !haveData,
          refreshing: haveData,
        );
      }
    }
    try {
      final ArenaSnapshot? snapshot;
      Conditional<ArenaSnapshot>? fetched;
      if (isPresentationDemo()) {
        snapshot = PresentationDemoData.arenaSnapshot(presentationUserId());
      } else {
        fetched = await _repo.getArenaSnapshotConditional(
          etag: state.hasData ? _etag : null,
        );
        snapshot = fetched.data;
      }
      if (generation != _generation) return; // superseded by a sign-out
      _snapshotLoadedAt = DateTime.now();
      if (snapshot == null) {
        // 304: nothing changed — keep the snapshot, just settle the flags.
        _etag = fetched?.etag ?? _etag;
        if (mounted &&
            (state.refreshing || state.loading || state.error != null)) {
          state = ArenaState(snapshot: state.snapshot);
        }
        return;
      }
      _etag = fetched?.etag;
      if (mounted) state = ArenaState(snapshot: snapshot);
      if (account != null && fetched?.raw != null) {
        _activeAccount = account;
        cache!.write(account, _cacheDomain, fetched!.raw, etag: _etag);
      }
    } on ApiException catch (e) {
      if (generation != _generation) return;
      if (e.statusCode == 401) {
        debugPrint('[ArenaController] 401 — triggering session expiry');
        if (mounted) state = state.copyWith(loading: false, refreshing: false);
        onSessionExpired?.call();
        return;
      }
      // Keep the cached snapshot visible on a failed background refresh.
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : 'Couldn\'t load races.',
        );
      }
    } catch (e, st) {
      if (generation != _generation) return;
      debugPrint('[ArenaController] unexpected error: $e\n$st');
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : 'Couldn\'t load races.',
        );
      }
    }
  }

  void clearSnapshot() {
    _snapshotLoadedAt = null;
    _etag = null;
    final account = _activeAccount ?? _cacheAccount();
    _activeAccount = null;
    if (account != null) cache?.clearAccount(account);
    // Drop any in-flight load so the next sign-in starts fresh rather than
    // awaiting a future from the previous session.
    _loadInFlight = null;
    // Invalidate any fetch already in flight — see [_generation] — so it
    // cannot land after this reset and resurrect the previous account's
    // snapshot into the new session.
    _generation++;
    if (mounted) state = const ArenaState();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final arenaApiProvider = Provider<ArenaApi>((_) => ArenaApi());

final arenaRepositoryProvider = Provider<ArenaRepository>((ref) {
  return ArenaRepository(
    ref.watch(arenaApiProvider),
    ref.watch(secureTokenStoreProvider),
    ref.watch(authApiProvider),
  );
});

final arenaControllerProvider =
    StateNotifierProvider<ArenaController, ArenaState>((ref) {
      final controller = ArenaController(
        ref.watch(arenaRepositoryProvider),
        isPresentationDemo: () =>
            isPresentationDemoUser(ref.read(authControllerProvider).user),
        presentationUserId: () =>
            ref.read(authControllerProvider).user?.id ?? '',
        cache: ref.read(cacheStoreProvider),
        accountId: () => ref.read(authControllerProvider).user?.id,
        onSessionExpired: () {
          debugPrint('[Arena] session expired — notifying AuthController');
          ref.read(authControllerProvider.notifier).sessionExpired();
        },
      );
      // Deferred: a synchronous mutation during the kickoff would modify
      // other providers while this one is still initializing (Riverpod
      // asserts).
      if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
        Future(() async {
          // Concurrent, never awaited: disk I/O must not delay the first fetch.
          unawaited(controller.hydrate());
          await controller.loadSnapshot(force: false);
        });
      }
      ref.listen<AuthState>(authControllerProvider, (prev, next) {
        if (next.status == AuthStatus.unauthenticated) {
          controller.clearSnapshot();
        } else if (next.status == AuthStatus.authenticated &&
            prev?.status != AuthStatus.authenticated) {
          () async {
            // Concurrent, never awaited: disk I/O must not delay the first fetch.
            unawaited(controller.hydrate());
            await controller.loadSnapshot(force: false);
          }();
        }
      });
      return controller;
    });
