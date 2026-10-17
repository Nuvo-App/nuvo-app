// The canonical notification inbox — docs/agents/18-data-freshness-contract.md.
// The in-app list is the source of truth; push (phase F) only calls markStale().
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_store.dart';
import '../../../core/demo/presentation_demo.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../social/domain/nuvo_destination.dart';
import '../data/notification_api.dart';
import '../data/notification_models.dart';
import '../data/notification_repository.dart';

class NotificationState {
  const NotificationState({
    this.items = const [],
    this.unreadCount = 0,
    this.nextCursor,
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
  });

  final List<NuvoNotification> items;
  final int unreadCount;
  final String? nextCursor;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;

  bool get hasData => items.isNotEmpty;
  bool get hasMore => nextCursor != null;

  NotificationState copyWith({
    List<NuvoNotification>? items,
    int? unreadCount,
    String? nextCursor,
    bool clearCursor = false,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    String? error,
  }) =>
      NotificationState(
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error,
      );
}

class NotificationController extends StateNotifier<NotificationState> {
  NotificationController(
    this._repo, {
    this.onSessionExpired,
    this.isPresentationDemo = _neverPresentationDemo,
    this.cache,
    this.accountId,
  }) : super(const NotificationState());

  // Disk snapshot (first page + cursor), per signed-in account.
  final CacheStore? cache;
  final String? Function()? accountId;
  static const _cacheDomain = 'notifications';
  static const _cacheMaxAge = Duration(days: 7);
  String? _etag;
  String? cacheAccount;
  bool _hydrated = false;

  final NotificationRepository _repo;
  final VoidCallback? onSessionExpired;

  /// Presentation/demo sessions never hit the API — fixture inbox only. The
  /// offline-demo sentinel token would 401 every call otherwise (and the
  /// resulting session-expired cascade would sign the demo out).
  final bool Function() isPresentationDemo;
  static bool _neverPresentationDemo() => false;

  static const cacheLifetime = Duration(minutes: 5);
  static const _staleWindow = Duration(seconds: 45);
  Future<void>? _loadInFlight;
  DateTime? _loadedAt;

  /// Bumped by [clear] (sign-out) — see the matching guard in
  /// RaceController._generation. Stops a fetch started before sign-out from
  /// landing after clear() and resurrecting the previous account's inbox
  /// into the new session.
  int _generation = 0;

  void revalidate() {
    final at = _loadedAt;
    if (state.hasData && at != null && DateTime.now().difference(at) < _staleWindow) {
      return;
    }
    load(force: true);
  }

  /// Push receipt / opening the bell.
  ///
  /// Lazy: only marks the inbox stale; fetches right away just when something
  /// is listening (bell / inbox on screen). Otherwise the next read refreshes.
  void markStale() {
    _loadedAt = null;
    if (mounted && hasListeners) load(force: true);
  }

  String? _validAccount() {
    if (cache == null) return null;
    final id = accountId?.call();
    return id != null && isValidCacheId(id) ? id : null;
  }

  /// Emits the disk snapshot (if any) without blocking the first frame.
  Future<void> _hydrate(int generation) async {
    if (_hydrated) return;
    _hydrated = true;
    final store = cache;
    final account = _validAccount();
    if (store == null || account == null) return;
    cacheAccount = account;
    try {
      final entry = await store.read(account, _cacheDomain, maxAge: _cacheMaxAge);
      if (generation != _generation || !mounted) return;
      final data = entry?.data;
      if (entry == null || data is! Map || state.hasData) return;
      final page = NotificationPage.fromJson(Map<String, dynamic>.from(data));
      _etag = entry.etag;
      state = NotificationState(
        items: page.items,
        unreadCount: page.unreadCount,
        nextCursor: page.nextCursor,
        refreshing: true,
      );
    } catch (_) {
      // A bad snapshot is just a cache miss.
    }
  }

  void _persist(NotificationPage page, int generation) {
    final store = cache;
    final account = cacheAccount ?? _validAccount();
    final raw = page.raw;
    if (store == null || account == null || raw == null) return;
    if (generation != _generation) return;
    cacheAccount = account;
    store.write(account, _cacheDomain, raw, etag: page.etag);
  }

  /// A local patch diverged from the server copy: forget the etag and drop
  /// the snapshot so a stale 304/hydration can never resurrect old data.
  void _invalidateCache() {
    _etag = null;
    final store = cache;
    final account = cacheAccount ?? _validAccount();
    if (store != null && account != null) {
      store.write(account, _cacheDomain, null);
    }
  }

  Future<void> load({bool force = true}) {
    final at = _loadedAt;
    if (!force && at != null && DateTime.now().difference(at) < cacheLifetime) {
      return Future.value();
    }
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetch();
    _loadInFlight = request;
    request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
    return request;
  }

  Future<void> _fetch() async {
    final generation = _generation;
    if (mounted) {
      state = state.copyWith(loading: !state.hasData, refreshing: state.hasData, error: null);
    }
    if (isPresentationDemo()) {
      if (mounted && generation == _generation) _applyFixtures();
      return;
    }
    try {
      await _hydrate(generation);
      if (generation != _generation) return;
      final sendEtag = state.hasData ? _etag : null;
      final page = await _repo.list(etag: sendEtag);
      if (generation != _generation) return; // superseded by a sign-out
      _loadedAt = DateTime.now();
      if (page.notModified) {
        if (mounted) {
          state = state.copyWith(loading: false, refreshing: false, error: null);
        }
        return;
      }
      _etag = page.etag;
      _persist(page, generation);
      if (mounted) {
        state = NotificationState(
          items: page.items,
          unreadCount: page.unreadCount,
          nextCursor: page.nextCursor,
        );
      }
    } on ApiException catch (e) {
      if (generation != _generation) return;
      // A demo session must never surface a network error — if the session
      // resolved as presentation mode mid-flight, fixtures win.
      if (isPresentationDemo()) {
        if (mounted) _applyFixtures();
        return;
      }
      if (e.statusCode == 401) {
        if (mounted) state = state.copyWith(loading: false, refreshing: false);
        onSessionExpired?.call();
        return;
      }
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : "Couldn't load notifications.",
        );
      }
    } catch (e, st) {
      if (generation != _generation) return;
      debugPrint('[NotificationController] $e\n$st');
      if (isPresentationDemo()) {
        if (mounted) _applyFixtures();
        return;
      }
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : "Couldn't load notifications.",
        );
      }
    }
  }

  void _applyFixtures() {
    final items = PresentationDemoData.notifications();
    _loadedAt = DateTime.now();
    state = NotificationState(
      items: items,
      unreadCount: items.where((n) => !n.read).length,
    );
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.loadingMore || isPresentationDemo()) return;
    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repo.list(cursor: cursor);
      if (generation != _generation) return; // superseded by a sign-out
      if (mounted) {
        state = state.copyWith(
          items: [...state.items, ...page.items],
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          unreadCount: page.unreadCount,
          loadingMore: false,
        );
      }
    } catch (_) {
      if (generation != _generation) return;
      if (mounted) state = state.copyWith(loadingMore: false);
    }
  }

  Future<void> markRead(String id) async {
    final item = state.items.firstWhere((n) => n.id == id, orElse: () => throw StateError('nf'));
    if (item.read) return;
    _invalidateCache();
    state = state.copyWith(
      items: state.items.map((n) => n.id == id ? n.copyWith(read: true) : n).toList(),
      unreadCount: (state.unreadCount - 1).clamp(0, 1 << 30),
    );
    if (isPresentationDemo()) return;
    try {
      await _repo.markRead(id);
    } catch (_) {/* optimistic; a refresh will reconcile */}
  }

  /// A crew mutation (accept/decline/remove/connect) just resolved the
  /// pending request from [userId]. The server marks its crew_request
  /// notifications read inside the same write; this mirrors that locally so
  /// the inbox and bell stop showing a stale actionable request immediately,
  /// without waiting for the next fetch.
  void resolveCrewRequest(String userId) {
    if (!mounted) return;
    var resolved = 0;
    final items = state.items.map((n) {
      final dest = n.destination;
      if (n.read ||
          n.category != 'crew_request' ||
          dest is! ProfileDestination ||
          dest.userId != userId) {
        return n;
      }
      resolved++;
      return n.copyWith(read: true);
    }).toList();
    if (resolved == 0) return;
    _invalidateCache();
    state = state.copyWith(
      items: items,
      unreadCount: (state.unreadCount - resolved).clamp(0, 1 << 30),
    );
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;
    _invalidateCache();
    state = state.copyWith(
      items: state.items.map((n) => n.copyWith(read: true)).toList(),
      unreadCount: 0,
    );
    if (isPresentationDemo()) return;
    try {
      await _repo.markAllRead();
    } catch (_) {}
  }

  void clear() {
    final account = cacheAccount;
    final store = cache;
    if (store != null && account != null) store.clearAccount(account);
    cacheAccount = null;
    _etag = null;
    _hydrated = false;
    _loadedAt = null;
    _loadInFlight = null;
    _generation++;
    if (mounted) state = const NotificationState();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _notificationApiProvider = Provider<NotificationApi>((_) => NotificationApi());

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    ref.watch(_notificationApiProvider),
    ref.watch(secureTokenStoreProvider),
    ref.watch(authApiProvider),
  );
});

final notificationControllerProvider =
    StateNotifierProvider<NotificationController, NotificationState>((ref) {
  final controller = NotificationController(
    ref.watch(notificationRepositoryProvider),
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).sessionExpired(),
    isPresentationDemo: () =>
        isPresentationDemoUser(ref.read(authControllerProvider).user),
    cache: ref.watch(cacheStoreProvider),
    accountId: () => ref.read(authControllerProvider).user?.id,
  );
  // Deferred: a synchronous mutation during the kickoff would modify other
  // providers while this one is still initializing (Riverpod asserts).
  if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
    Future(() => controller.load(force: false));
  }
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    if (next.status == AuthStatus.unauthenticated) {
      controller.clear();
    } else if (next.status == AuthStatus.authenticated &&
        (prev?.status != AuthStatus.authenticated ||
            prev?.user?.id != next.user?.id)) {
      // A different signed-in user must never see the previous inbox.
      controller.clear();
      controller.load(force: false);
    }
  });
  ref.listen<bool>(presentationModeEnabledProvider, (_, _) {
    // Toggling presentation mode swaps fixture ↔ real inbox entirely.
    controller.clear();
    if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
      controller.load(force: true);
    }
  });
  return controller;
});

/// Just the badge count — cheap to watch from an app-bar bell.
final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationControllerProvider).unreadCount,
);
