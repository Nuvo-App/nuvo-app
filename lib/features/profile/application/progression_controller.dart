import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/progression_api.dart';
import '../data/progression_models.dart';

/// Mirrors the server's FEATURED_BADGE_SLOTS — kept as a client constant
/// only so the UI can gate taps before the round-trip; the server still
/// validates the write.
const featuredSlots = 3;

/// Nuvo Levels — the user's server-owned progression state. Loaded lazily
/// when Profile (or any level surface) reads it, refreshed after race
/// mutations, and cleared on sign-out so account switching never leaks XP.
class ProgressionController
    extends StateNotifier<AsyncValue<NuvoProgression>> {
  ProgressionController(this._api, this._store)
      : super(const AsyncValue.loading());

  final ProgressionApi _api;
  final SecureTokenStore _store;

  static const _staleWindow = Duration(seconds: 45);
  DateTime? _loadedAt;

  Future<String> _token() async {
    final token = await _store.getAccessToken();
    if (token == null) throw const ApiException(401, 'Not authenticated');
    return token;
  }

  /// Fetch (or refetch) the authoritative progression payload. The server
  /// reconciles XP from canonical race events on read, so this is always
  /// current after race actions — no separate invalidation pipeline needed.
  Future<void> load({bool force = true}) async {
    if (!force &&
        state.hasValue &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < _staleWindow) {
      return;
    }
    try {
      final progression = await _api.getProgression(await _token());
      if (!mounted) return;
      _loadedAt = DateTime.now();
      state = AsyncValue.data(progression);
    } catch (e, st) {
      if (!mounted) return;
      // Keep the last good payload visible on refresh failure — progression
      // is a read-through cache, not a gate.
      if (!state.hasValue) state = AsyncValue.error(e, st);
    }
  }

  /// Acknowledge the level-up moment — server persists it so it never
  /// replays across restarts, reinstalls, or account switches.
  Future<void> markLevelSeen() async {
    try {
      final progression = await _api.markLevelSeen(await _token());
      if (!mounted) return;
      _loadedAt = DateTime.now();
      state = AsyncValue.data(progression);
    } catch (_) {
      // Acknowledgment failure is safe — worst case the moment presents once
      // more on the next successful read.
    }
  }

  Future<List<NuvoBadge>> getBadges() async =>
      _api.getBadges(await _token());

  /// Optimistically keep the featured set in the cached payload after a
  /// successful write — the badges screen refetches for the full collection.
  Future<List<NuvoBadge>> setFeatured(List<String> unlockIds) async {
    final badges = await _api.setFeatured(await _token(), unlockIds);
    final current = state.valueOrNull;
    if (mounted && current != null) {
      state = AsyncValue.data(
        NuvoProgression(
          level: current.level,
          totalXp: current.totalXp,
          currentLevelXp: current.currentLevelXp,
          nextLevelXp: current.nextLevelXp,
          progress: current.progress,
          xpToNext: current.xpToNext,
          lastSeenLevel: current.lastSeenLevel,
          nextUnlock: current.nextUnlock,
          levelUnlock: current.levelUnlock,
          featuredBadges: badges.where((b) => b.featured).toList(),
        ),
      );
    }
    return badges;
  }

  void clear() {
    _loadedAt = null;
    state = const AsyncValue.loading();
  }
}

final progressionApiProvider = Provider<ProgressionApi>(
  (_) => ProgressionApi(),
);

final progressionControllerProvider =
    StateNotifierProvider<ProgressionController, AsyncValue<NuvoProgression>>(
  (ref) {
    final controller = ProgressionController(
      ref.watch(progressionApiProvider),
      ref.watch(secureTokenStoreProvider),
    );
    if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
      controller.load();
    }
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.status == AuthStatus.unauthenticated) {
        controller.clear();
      } else if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        controller.load();
      }
    });
    return controller;
  },
);
