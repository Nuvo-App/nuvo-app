import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/progression_api.dart';
import '../data/progression_models.dart';

/// Featured slots come from the server's level unlock ladder (base 1, +1
/// per slot unlock) — the payload carries the count; nothing client-side
/// hardcodes it.

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
            featuredSlots: p.featuredSlots,
            achievementsEarned: p.achievementsEarned,
            achievementsTotal: p.achievementsTotal,
            nextUnlock: p.nextUnlock,
            levelUnlock: p.levelUnlock,
            nextAchievement: p.nextAchievement,
            featuredBadges: p.featuredBadges,
            newlyEarned: p.newlyEarned,
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
            category: b.category,
            iconKey: b.iconKey,
            statKey: b.statKey,
            threshold: b.threshold,
            progressValue: b.progressValue,
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
          featuredSlots: current.featuredSlots,
          achievementsEarned: current.achievementsEarned,
          achievementsTotal: current.achievementsTotal,
          nextUnlock: current.nextUnlock,
          levelUnlock: current.levelUnlock,
          nextAchievement: current.nextAchievement,
          featuredBadges: badges.where((b) => b.featured).toList(),
          newlyEarned: current.newlyEarned,
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
        featuredSlots: p.featuredSlots,
        achievementsEarned: p.achievementsEarned,
        achievementsTotal: p.achievementsTotal,
        nextUnlock: p.nextUnlock,
        levelUnlock: p.levelUnlock,
        nextAchievement: p.nextAchievement,
        featuredBadges: _demoBadges!.where((b) => b.featured).toList(),
        newlyEarned: p.newlyEarned,
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

// Level 8, mid-climb: 12 of 44 earned, three featured (L2+L7 slots), a
// nearly-complete Hat Trick as the reason to race again. Every locked row
// carries canonical-style progress — the fixture mirrors the payload, it
// doesn't pretend to be the ledger.
NuvoProgression _demoProgression() => NuvoProgression(
      level: 8,
      totalXp: 1240,
      currentLevelXp: 40,
      nextLevelXp: 180,
      progress: 40 / 180,
      xpToNext: 140,
      // lastSeen == level — the demo never fires the level-up moment on open.
      lastSeenLevel: 8,
      featuredSlots: 3,
      achievementsEarned: 14,
      achievementsTotal: _demoBadgeCollection().length,
      nextUnlock: const NuvoUnlockRef(
        unlockId: 'cap-reaction-clap',
        level: 9,
        type: 'reaction',
        key: 'clap',
        name: 'Clap reaction',
        description: 'A new reaction for race finishes.',
      ),
      nextAchievement: _demoBadge('ach-hat-trick'),
      featuredBadges: [
        _demoBadge('ach-first-w'),
        _demoBadge('ach-five-deep'),
        _demoBadge('ach-personal-best'),
      ],
    );

NuvoBadge _ach(
  String id,
  String key,
  String name,
  String desc,
  String category,
  String icon,
  String stat,
  int threshold,
  int progress,
  bool earned, {
  int position = -1,
  String rarity = 'common',
}) =>
    NuvoBadge(
      unlockId: id,
      type: 'achievement',
      key: key,
      name: name,
      description: desc,
      requiredLevel: 0,
      metadata: {'rarity': rarity},
      unlocked: earned,
      unlockedAt: earned ? 'demo' : null,
      featured: position >= 0,
      position: position >= 0 ? position : null,
      category: category,
      iconKey: icon,
      statKey: stat,
      threshold: threshold,
      progressValue: progress,
    );

NuvoBadge _demoBadge(String id) =>
    _demoBadgeCollection().firstWhere((b) => b.unlockId == id);

List<NuvoBadge> _demoBadgeCollection() => [
      // Racing
      _ach('ach-first-move', 'first_move', 'First Move', 'Submit your first accepted progress.', 'racing', 'arrow_forward', 'progresses_accepted', 1, 1, true),
      _ach('ach-on-the-board', 'on_the_board', 'On the Board', 'Finish your first race.', 'racing', 'flag', 'races_finished', 1, 1, true),
      _ach('ach-five-deep', 'five_deep', 'Five Deep', 'Finish 5 races.', 'racing', 'flags_5', 'races_finished', 5, 5, true, position: 1, rarity: 'uncommon'),
      _ach('ach-double-digits', 'double_digits', 'Double Digits', 'Finish 10 races.', 'racing', 'num_10', 'races_finished', 10, 8, false, rarity: 'milestone'),
      _ach('ach-quarter-century', 'quarter_century', 'Quarter Century', 'Finish 25 races.', 'racing', 'num_25', 'races_finished', 25, 8, false, rarity: 'milestone'),
      _ach('ach-fifty-strong', 'fifty_strong', 'Fifty Strong', 'Finish 50 races.', 'racing', 'num_50', 'races_finished', 50, 8, false, rarity: 'milestone'),
      _ach('ach-century', 'century', 'Century', 'Finish 100 races.', 'racing', 'num_100', 'races_finished', 100, 8, false, rarity: 'legendary'),
      // Winning
      _ach('ach-first-w', 'first_w', 'First W', 'Win your first race.', 'winning', 'trophy_1', 'races_won', 1, 1, true, position: 0),
      _ach('ach-hat-trick', 'hat_trick', 'Hat Trick', 'Win 3 races.', 'winning', 'trophy_3', 'races_won', 3, 2, false, rarity: 'uncommon'),
      _ach('ach-high-five', 'high_five', 'High Five', 'Win 5 races.', 'winning', 'trophy_5', 'races_won', 5, 2, false, rarity: 'uncommon'),
      _ach('ach-ten-up', 'ten_up', 'Ten Up', 'Win 10 races.', 'winning', 'trophy_10', 'races_won', 10, 2, false, rarity: 'milestone'),
      _ach('ach-twentyfive-wins', 'twentyfive_wins', "Twenty-Five W's", 'Win 25 races.', 'winning', 'trophy_25', 'races_won', 25, 2, false, rarity: 'milestone'),
      _ach('ach-champion', 'champion', 'Champion', 'Win 50 races.', 'winning', 'crown', 'races_won', 50, 2, false, rarity: 'legendary'),
      // Creation
      _ach('ach-race-maker', 'race_maker', 'Race Maker', 'Create 3 races.', 'creation', 'flag_plus', 'races_created', 3, 3, true, rarity: 'uncommon'),
      _ach('ach-starter-pack', 'starter_pack', 'Starter Pack', 'Create 10 races.', 'creation', 'flags_stack', 'races_created', 10, 3, false, rarity: 'milestone'),
      _ach('ach-race-architect', 'race_architect', 'Race Architect', 'Create 25 races.', 'creation', 'blueprint', 'races_created', 25, 3, false, rarity: 'legendary'),
      // Performance
      _ach('ach-personal-best', 'personal_best', 'Personal Best', 'Set your first personal best.', 'performance', 'spark_up', 'pbs_set', 1, 1, true, position: 2),
      _ach('ach-getting-better', 'getting_better', 'Getting Better', 'Set 10 personal bests.', 'performance', 'chart_up', 'pbs_set', 10, 4, false, rarity: 'milestone'),
      _ach('ach-comeback', 'comeback', 'Comeback', 'Win a race after trailing.', 'performance', 'arrow_curve', 'comebacks', 1, 1, true, rarity: 'uncommon'),
      _ach('ach-wire-to-wire', 'wire_to_wire', 'Wire to Wire', 'Lead from first result to the finish.', 'performance', 'crown_line', 'wire_to_wires', 1, 0, false, rarity: 'milestone'),
      // Social
      _ach('ach-crewmate', 'crewmate', 'Crewmate', 'Finish 5 races with other people.', 'social', 'people', 'social_finished', 5, 5, true, rarity: 'uncommon'),
      _ach('ach-crowd-favorite', 'crowd_favorite', 'Crowd Favorite', 'Finish a race with 10+ racers.', 'social', 'people_flag', 'big_race_finished', 1, 0, false, rarity: 'milestone'),
      _ach('ach-rivalry', 'rivalry', 'Rivalry', 'Finish 5 races against the same racer.', 'social', 'crossed_flags', 'rivalry_max', 5, 3, false, rarity: 'milestone'),
      // Variety
      _ach('ach-variety-pack', 'variety_pack', 'Variety Pack', 'Finish races in 4 categories.', 'variety', 'tiles_4', 'distinct_categories', 4, 4, true, rarity: 'uncommon'),
      _ach('ach-all-rounder', 'all_rounder', 'All-Rounder', 'Finish races in 8 categories.', 'variety', 'compass', 'distinct_categories', 8, 4, false, rarity: 'milestone'),
      // Motion
      _ach('ach-motion-rookie', 'motion_rookie', 'Movement Rookie', 'Finish your first motion race.', 'motion', 'motion_figure', 'motion_finished', 1, 1, true),
      _ach('ach-motion-regular', 'motion_regular', 'Motion Regular', 'Finish 10 motion races.', 'motion', 'motion_10', 'motion_finished', 10, 6, false, rarity: 'milestone'),
      _ach('ach-motion-machine', 'motion_machine', 'Motion Machine', 'Finish 50 motion races.', 'motion', 'motion_bolt', 'motion_finished', 50, 6, false, rarity: 'legendary'),
      // Proof / format
      _ach('ach-photo-finish', 'photo_finish', 'Photo Finish', 'Finish your first photo-proof race.', 'proof', 'camera', 'photo_finished', 1, 1, true),
      _ach('ach-proof-collector', 'proof_collector', 'Proof Collector', 'Get 10 accepted photo proofs.', 'proof', 'camera_check', 'photo_proofs', 10, 3, false, rarity: 'milestone'),
      _ach('ach-time-trial', 'time_trial', 'Time Trial', 'Finish your first timed race.', 'proof', 'stopwatch', 'timed_finished', 1, 1, true),
      _ach('ach-against-the-clock', 'against_the_clock', 'Against the Clock', 'Finish 10 timed races.', 'proof', 'stopwatch_bolt', 'timed_finished', 10, 1, false, rarity: 'milestone'),
      // Category families
      _ach('ach-book-it', 'book_it', 'Book It', 'Finish your first reading race.', 'category', 'book', 'category:reading', 1, 1, true, rarity: 'uncommon'),
      _ach('ach-page-turner', 'page_turner', 'Page Turner', 'Finish 10 reading races.', 'category', 'books_stack', 'category:reading', 10, 2, false, rarity: 'milestone'),
      _ach('ach-brain-race', 'brain_race', 'Brain Race', 'Finish your first academic race.', 'category', 'paper_grade', 'category:academic', 1, 0, false, rarity: 'uncommon'),
      _ach('ach-scholar', 'scholar', 'Scholar', 'Finish 10 academic races.', 'category', 'cap_grad', 'category:academic', 10, 0, false, rarity: 'milestone'),
      _ach('ach-on-the-green', 'on_the_green', 'On the Green', 'Finish your first golf race.', 'category', 'flag_golf', 'category:golf', 1, 0, false, rarity: 'uncommon'),
      _ach('ach-clubhouse-regular', 'clubhouse_regular', 'Clubhouse Regular', 'Finish 10 golf races.', 'category', 'flag_golf_10', 'category:golf', 10, 0, false, rarity: 'milestone'),
      // Level milestones
      _ach('ach-level-5', 'level_5', 'Level 5', 'Reach Level 5.', 'level', 'num_5', '', 5, 0, true, rarity: 'uncommon'),
      _ach('ach-level-10', 'level_10', 'Level 10', 'Reach Level 10.', 'level', 'num_10', '', 10, 0, false, rarity: 'milestone'),
      _ach('ach-level-25', 'level_25', 'Level 25', 'Reach Level 25.', 'level', 'num_25', '', 25, 0, false, rarity: 'milestone'),
      _ach('ach-level-50', 'level_50', 'Level 50', 'Reach Level 50.', 'level', 'num_50', '', 50, 0, false, rarity: 'legendary'),
      _ach('ach-level-100', 'level_100', 'Level 100', 'Reach Level 100.', 'level', 'num_100', '', 100, 0, false, rarity: 'legendary'),
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
