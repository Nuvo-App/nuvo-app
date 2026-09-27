import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo/presentation_demo.dart';
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
  ProgressionController(
    this._api,
    this._store, {
    bool Function()? isPresentationDemo,
  })  : _isPresentationDemo = isPresentationDemo ?? (() => false),
        super(const AsyncValue.loading());

  final ProgressionApi _api;
  final SecureTokenStore _store;

  /// Presentation/demo identities read fixtures, not the API — same contract
  /// as the race list. The real system never depends on this path.
  final bool Function() _isPresentationDemo;
  List<NuvoBadge>? _demoBadges;

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
    if (_isPresentationDemo()) {
      _loadedAt = DateTime.now();
      state = AsyncValue.data(_demoProgression());
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
    if (_isPresentationDemo()) {
      final p = state.valueOrNull;
      if (mounted && p != null) {
        state = AsyncValue.data(
          NuvoProgression(
            level: p.level,
            totalXp: p.totalXp,
            currentLevelXp: p.currentLevelXp,
            nextLevelXp: p.nextLevelXp,
            progress: p.progress,
            xpToNext: p.xpToNext,
            lastSeenLevel: p.level,
            nextUnlock: p.nextUnlock,
            levelUnlock: p.levelUnlock,
            featuredBadges: p.featuredBadges,
          ),
        );
      }
      return;
    }
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

  Future<List<NuvoBadge>> getBadges() async {
    if (_isPresentationDemo()) {
      return _demoBadges ??= _demoBadgeCollection();
    }
    return _api.getBadges(await _token());
  }

  /// Optimistically keep the featured set in the cached payload after a
  /// successful write — the badges screen refetches for the full collection.
  Future<List<NuvoBadge>> setFeatured(List<String> unlockIds) async {
    if (_isPresentationDemo()) {
      final base = _demoBadges ??= _demoBadgeCollection();
      _demoBadges = [
        for (final b in base)
          NuvoBadge(
            unlockId: b.unlockId,
            type: b.type,
            key: b.key,
            name: b.name,
            description: b.description,
            requiredLevel: b.requiredLevel,
            metadata: b.metadata,
            unlocked: b.unlocked,
            unlockedAt: b.unlockedAt,
            featured: b.unlocked && unlockIds.contains(b.unlockId),
            position: b.unlocked ? unlockIds.indexOf(b.unlockId) : null,
          ),
      ];
      _syncDemoFeatured();
      return _demoBadges!;
    }
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

  void _syncDemoFeatured() {
    final p = state.valueOrNull;
    if (!mounted || p == null || _demoBadges == null) return;
    state = AsyncValue.data(
      NuvoProgression(
        level: p.level,
        totalXp: p.totalXp,
        currentLevelXp: p.currentLevelXp,
        nextLevelXp: p.nextLevelXp,
        progress: p.progress,
        xpToNext: p.xpToNext,
        lastSeenLevel: p.lastSeenLevel,
        nextUnlock: p.nextUnlock,
        levelUnlock: p.levelUnlock,
        featuredBadges: _demoBadges!.where((b) => b.featured).toList(),
      ),
    );
  }

  void clear() {
    _loadedAt = null;
    _demoBadges = null;
    state = const AsyncValue.loading();
  }
}

// ── Presentation/demo fixtures ──────────────────────────────────────────────
// The review account has no canonical race history, so its level story is a
// fixture — same contract as the demo race list. Real accounts never read
// these values; the server is the only XP authority.

NuvoProgression _demoProgression() => const NuvoProgression(
      level: 8,
      totalXp: 1240,
      currentLevelXp: 40,
      nextLevelXp: 180,
      progress: 40 / 180,
      xpToNext: 140,
      // lastSeen == level — the demo never fires the level-up moment on open.
      lastSeenLevel: 8,
      nextUnlock: NuvoUnlockRef(
        unlockId: 'bdg-double-digits',
        level: 10,
        type: 'badge',
        key: 'double_digits',
        name: 'Double Digits',
        description: 'Two digits of real competition.',
        metadata: {'icon': 'medal', 'rarity': 'milestone'},
      ),
      featuredBadges: [
        NuvoBadge(
          unlockId: 'bdg-five-deep',
          type: 'badge',
          key: 'five_deep',
          name: 'Five Deep',
          requiredLevel: 5,
          metadata: {'icon': 'flame', 'rarity': 'milestone'},
          unlocked: true,
          featured: true,
          position: 0,
        ),
        NuvoBadge(
          unlockId: 'bdg-off-the-line',
          type: 'badge',
          key: 'off_the_line',
          name: 'Off the Line',
          requiredLevel: 2,
          metadata: {'icon': 'flag', 'rarity': 'standard'},
          unlocked: true,
          featured: true,
          position: 1,
        ),
      ],
    );

List<NuvoBadge> _demoBadgeCollection() => [
      const NuvoBadge(
        unlockId: 'bdg-off-the-line',
        type: 'badge',
        key: 'off_the_line',
        name: 'Off the Line',
        requiredLevel: 2,
        metadata: {'icon': 'flag', 'rarity': 'standard'},
        unlocked: true,
        featured: true,
        position: 1,
      ),
      const NuvoBadge(
        unlockId: 'bdg-in-motion',
        type: 'badge',
        key: 'in_motion',
        name: 'In Motion',
        requiredLevel: 3,
        metadata: {'icon': 'bolt', 'rarity': 'standard'},
        unlocked: true,
        featured: false,
      ),
      const NuvoBadge(
        unlockId: 'bdg-five-deep',
        type: 'badge',
        key: 'five_deep',
        name: 'Five Deep',
        requiredLevel: 5,
        metadata: {'icon': 'flame', 'rarity': 'milestone'},
        unlocked: true,
        featured: true,
        position: 0,
      ),
      const NuvoBadge(
        unlockId: 'bdg-locked-in',
        type: 'badge',
        key: 'locked_in',
        name: 'Locked In',
        requiredLevel: 7,
        metadata: {'icon': 'target', 'rarity': 'standard'},
        unlocked: true,
        featured: false,
      ),
      const NuvoBadge(
        unlockId: 'bdg-double-digits',
        type: 'badge',
        key: 'double_digits',
        name: 'Double Digits',
        requiredLevel: 10,
        metadata: {'icon': 'medal', 'rarity': 'milestone'},
        unlocked: false,
        featured: false,
      ),
      const NuvoBadge(
        unlockId: 'bdg-built-different',
        type: 'badge',
        key: 'built_different',
        name: 'Built Different',
        requiredLevel: 15,
        metadata: {'icon': 'trophy', 'rarity': 'milestone'},
        unlocked: false,
        featured: false,
      ),
      const NuvoBadge(
        unlockId: 'bdg-veteran',
        type: 'badge',
        key: 'veteran',
        name: 'Veteran',
        requiredLevel: 20,
        metadata: {'icon': 'crown', 'rarity': 'milestone'},
        unlocked: false,
        featured: false,
      ),
      const NuvoBadge(
        unlockId: 'bdg-unstoppable',
        type: 'badge',
        key: 'unstoppable',
        name: 'Unstoppable',
        requiredLevel: 25,
        metadata: {'icon': 'star', 'rarity': 'milestone'},
        unlocked: false,
        featured: false,
      ),
    ];

final progressionApiProvider = Provider<ProgressionApi>(
  (_) => ProgressionApi(),
);

final progressionControllerProvider =
    StateNotifierProvider<ProgressionController, AsyncValue<NuvoProgression>>(
  (ref) {
    final controller = ProgressionController(
      ref.watch(progressionApiProvider),
      ref.watch(secureTokenStoreProvider),
      isPresentationDemo: () =>
          isPresentationDemoUser(ref.read(authControllerProvider).user),
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
