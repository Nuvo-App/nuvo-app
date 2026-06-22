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
    : super(const ArenaState()) {
    loadSnapshot();
  }

  final ArenaRepository _repo;
  final VoidCallback? onSessionExpired;

  Future<void> loadSnapshot() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final snapshot = await _repo.getArenaSnapshot();
      if (mounted) state = state.copyWith(snapshot: snapshot, loading: false);
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
      ref.listen<AuthState>(authControllerProvider, (prev, next) {
        if (next.status == AuthStatus.unauthenticated) {
          controller.clearSnapshot();
        } else if (next.status == AuthStatus.authenticated &&
            prev?.status != AuthStatus.authenticated) {
          controller.loadSnapshot();
        }
      });
      return controller;
    });
