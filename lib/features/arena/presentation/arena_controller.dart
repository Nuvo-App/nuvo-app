// Arena next-move snapshot state. Same shape and rules as RaceController
// (docs/agents/08 provider graph, docs/agents/10 §A1): StateNotifierProvider is
// not recreated on sign-out, so clearSnapshot() must null the cache timestamp
// AND the in-flight future or a hung load wedges the tab until an app kill.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/arena_api.dart';
import '../data/arena_models.dart';
import '../data/arena_repository.dart';

class ArenaState {
  const ArenaState({this.snapshot, this.loading = false, this.error});

  final ArenaSnapshot? snapshot;
  final bool loading;
  final String? error;

  ArenaState copyWith({
    ArenaSnapshot? snapshot,
    bool? loading,
    String? error,
  }) => ArenaState(
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    error: error,
  );
}

class ArenaController extends StateNotifier<ArenaState> {
  ArenaController(this._repo, {this.onSessionExpired})
    : super(const ArenaState());

  final ArenaRepository _repo;
  final VoidCallback? onSessionExpired;
  static const _cacheLifetime = Duration(minutes: 5);
  Future<void>? _loadInFlight;
  DateTime? _snapshotLoadedAt;

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
    if (mounted) state = ArenaState(snapshot: state.snapshot, loading: true);
    try {
      final snapshot = await _repo.getArenaSnapshot();
      _snapshotLoadedAt = DateTime.now();
      if (mounted) state = ArenaState(snapshot: snapshot);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        debugPrint('[ArenaController] 401 — triggering session expiry');
        if (mounted) state = state.copyWith(loading: false);
        onSessionExpired?.call();
        return;
      }
      if (mounted) {
        state = state.copyWith(loading: false, error: 'Couldn\'t load races.');
      }
    } catch (e, st) {
      debugPrint('[ArenaController] unexpected error: $e\n$st');
      if (mounted) {
        state = state.copyWith(loading: false, error: 'Couldn\'t load races.');
      }
    }
  }

  void clearSnapshot() {
    _snapshotLoadedAt = null;
    // Drop any in-flight load so the next sign-in starts fresh rather than
    // awaiting a future from the previous session.
    _loadInFlight = null;
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
        onSessionExpired: () {
          debugPrint('[Arena] session expired — notifying AuthController');
          ref.read(authControllerProvider.notifier).sessionExpired();
        },
      );
      if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
        controller.loadSnapshot(force: false);
      }
      ref.listen<AuthState>(authControllerProvider, (prev, next) {
        if (next.status == AuthStatus.unauthenticated) {
          controller.clearSnapshot();
        } else if (next.status == AuthStatus.authenticated &&
            prev?.status != AuthStatus.authenticated) {
          controller.loadSnapshot(force: false);
        }
      });
      return controller;
    });
