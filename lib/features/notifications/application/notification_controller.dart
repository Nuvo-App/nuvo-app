// The canonical notification inbox — docs/agents/18-data-freshness-contract.md.
// The in-app list is the source of truth; push (phase F) only calls markStale().
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
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
  NotificationController(this._repo, {this.onSessionExpired})
      : super(const NotificationState());

  final NotificationRepository _repo;
  final VoidCallback? onSessionExpired;

  static const _cacheLifetime = Duration(minutes: 5);
  static const _staleWindow = Duration(seconds: 45);
  Future<void>? _loadInFlight;
  DateTime? _loadedAt;

  void revalidate() {
    final at = _loadedAt;
    if (state.hasData && at != null && DateTime.now().difference(at) < _staleWindow) {
      return;
    }
    load(force: true);
  }

  /// Push receipt / opening the bell.
  void markStale() {
    _loadedAt = null;
    if (mounted) load(force: true);
  }

  Future<void> load({bool force = true}) {
    final at = _loadedAt;
    if (!force && at != null && DateTime.now().difference(at) < _cacheLifetime) {
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
    if (mounted) {
      state = state.copyWith(loading: !state.hasData, refreshing: state.hasData, error: null);
    }
    try {
      final page = await _repo.list();
      _loadedAt = DateTime.now();
      if (mounted) {
        state = NotificationState(
          items: page.items,
          unreadCount: page.unreadCount,
          nextCursor: page.nextCursor,
        );
      }
    } on ApiException catch (e) {
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
      debugPrint('[NotificationController] $e\n$st');
      if (mounted) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: state.hasData ? null : "Couldn't load notifications.",
        );
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.loadingMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repo.list(cursor: cursor);
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
      if (mounted) state = state.copyWith(loadingMore: false);
    }
  }

  Future<void> markRead(String id) async {
    final item = state.items.firstWhere((n) => n.id == id, orElse: () => throw StateError('nf'));
    if (item.read) return;
    state = state.copyWith(
      items: state.items.map((n) => n.id == id ? n.copyWith(read: true) : n).toList(),
      unreadCount: (state.unreadCount - 1).clamp(0, 1 << 30),
    );
    try {
      await _repo.markRead(id);
    } catch (_) {/* optimistic; a refresh will reconcile */}
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;
    state = state.copyWith(
      items: state.items.map((n) => n.copyWith(read: true)).toList(),
      unreadCount: 0,
    );
    try {
      await _repo.markAllRead();
    } catch (_) {}
  }

  void clear() {
    _loadedAt = null;
    _loadInFlight = null;
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
  );
  if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
    controller.load(force: false);
  }
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    if (next.status == AuthStatus.unauthenticated) {
      controller.clear();
    } else if (next.status == AuthStatus.authenticated &&
        prev?.status != AuthStatus.authenticated) {
      controller.load(force: false);
    }
  });
  return controller;
});

/// Just the badge count — cheap to watch from an app-bar bell.
final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationControllerProvider).unreadCount,
);
