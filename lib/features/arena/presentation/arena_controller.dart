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
  ArenaController(this._repo) : super(const ArenaState()) {
    loadSnapshot();
  }

  final ArenaRepository _repo;

  Future<void> loadSnapshot() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final snapshot = await _repo.getArenaSnapshot();
      if (mounted) state = state.copyWith(snapshot: snapshot, loading: false);
    } on ApiException catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: e.message);
    } catch (_) {
      if (mounted) {
        state = state.copyWith(loading: false, error: 'Failed to load arena.');
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
      final controller = ArenaController(ref.watch(arenaRepositoryProvider));
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
