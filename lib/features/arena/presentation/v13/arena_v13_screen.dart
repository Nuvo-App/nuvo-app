import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/race_display.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';

import '../arena_controller.dart';
import 'arena_v13_data.dart';
import 'arena_v13_race_swiper.dart';
import 'arena_v13_sections.dart';

/// The v13 Arena tab — `/arena` (also mounted by the shell as the home tab).
///
/// Route contract: no path or query params; `extra` is ignored. The widget
/// reads everything from existing providers — races + viewerContext from
/// [raceControllerProvider], board order from [arenaControllerProvider],
/// streak/level/record from [progressionControllerProvider], the bell badge
/// from [unreadCountProvider], the nudge from [crewActivityProvider], and the
/// 18-week heat map from [arenaActivityProvider].
class ArenaScreenV13 extends ConsumerStatefulWidget {
  const ArenaScreenV13({super.key});

  @override
  ConsumerState<ArenaScreenV13> createState() => _ArenaScreenV13State();
}

class _ArenaScreenV13State extends ConsumerState<ArenaScreenV13> {
  /// Last-seen (score, rank) per race id. Seeded the first time each race is
  /// sighted, diffed on every later update — a proof that lands while the
  /// user is away pushes a "+N" float over the card on return.
  final Map<String, ({int score, int? rank})> _seen = {};
  final Map<String, int> _plusBursts = {};
  ProviderSubscription<RaceState>? _raceSub;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _raceSub = ref.listenManual(
      raceControllerProvider,
      (_, next) => _syncStandings(next.races),
    );
    // Same self-kick the shell gives tabs — keeps the screen live when it's
    // mounted as a plain pushed route (and inside tests). Every revalidate
    // is a no-op while the cached payload is inside its stale window.
    final openedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(analyticsProvider).screen(
        'arena',
        ms: DateTime.now().difference(openedAt).inMilliseconds,
      );
    });
    Future(() {
      ref.read(raceControllerProvider.notifier).revalidate();
      ref.read(arenaControllerProvider.notifier).revalidate();
      ref.read(progressionControllerProvider.notifier).revalidate();
      ref.read(notificationControllerProvider.notifier).revalidate();
      ref.read(crewActivityProvider.notifier).revalidate();
    });
  }

  @override
  void dispose() {
    _raceSub?.close();
    super.dispose();
  }

  void _syncStandings(List<Race> races) {
    final myId = ref.read(authControllerProvider).user?.id;
    final bursts = <String, int>{};
    for (final race in races.where(raceIsActive)) {
      final score = arenaViewerScore(race, myId);
      final rank = race.viewerContext?.rank ?? positionalRank(race, myId);
      final last = _seen[race.id];
      _seen[race.id] = (score: score, rank: rank);
      if (last != null && score > last.score) {
        bursts[race.id] = score - last.score;
      }
    }
    if (bursts.isNotEmpty && mounted) {
      V13Haptics.confirm();
      setState(() => _plusBursts.addAll(bursts));
    }
  }

  void _clearBurst(String raceId) => setState(() => _plusBursts.remove(raceId));

  Future<void> _refresh() async {
    ref.invalidate(arenaActivityProvider);
    ref.invalidate(arenaBadgeCollectionProvider);
    await Future.wait([
      ref.read(raceControllerProvider.notifier).loadRaces(force: true),
      ref.read(arenaControllerProvider.notifier).loadSnapshot(force: true),
      ref.read(progressionControllerProvider.notifier).load(force: true),
      ref.read(notificationControllerProvider.notifier).load(force: true),
      ref.read(crewActivityProvider.notifier).load(force: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final myId = auth.user?.id;
    final raceState = ref.watch(raceControllerProvider);
    final arenaState = ref.watch(arenaControllerProvider);
    final progression = ref.watch(progressionControllerProvider);
    final unread = ref.watch(unreadCountProvider);
    final feed = ref.watch(crewActivityProvider);
    final activity = ref.watch(arenaActivityProvider);
    final badgeCollection = ref.watch(arenaBadgeCollectionProvider);

    // First sight seeds the reward baseline — cold-cache data must not pop.
    if (!_seeded && raceState.races.isNotEmpty) {
      _seeded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncStandings(raceState.races);
      });
    }

    final races = arenaOrderedRaces(raceState.races, arenaState.snapshot);
    final cards = [for (final r in races) arenaCardData(r, myId)];
    final progressionValue = progression.valueOrNull;
    final nudge = pickArenaNudge(
      items: feed.items,
      activeRaces: races,
      myId: myId,
    );
    final stats = arenaStats(progressionValue?.record, raceState.races, myId);

    return ColoredBox(
      color: V13.bg,
      child: RefreshIndicator(
        color: V13.blue,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: V13.gapLg,
            bottom: V13TabBar.bottomPadding(context),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: ArenaHeader(
                firstName: arenaFirstName(
                  auth.user?.fullName,
                  auth.user?.username,
                ),
                streakDays: progressionValue?.record?.streakDays,
                level: progressionValue?.level,
                levelLoading: progression.isLoading && !progression.hasValue,
                xpProgress: progressionValue?.progress ?? 0,
                photoUrl: auth.user?.profilePhotoUrl,
                unreadCount: unread,
                onBellTap: () => context.push('/notifications'),
                onAvatarTap: () => context.go('/profile'),
              ),
            ),
            const SizedBox(height: V13.gapXxl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: V13SectionHeader(
                title: raceState.hasData
                    ? 'Your races · ${cards.length}'
                    : 'Your races',
                trailingLabel: cards.isNotEmpty ? 'Swipe for more' : null,
              ),
            ),
            const SizedBox(height: V13.gapMd),
            _racesSection(raceState, cards),
            const SizedBox(height: V13.gapSection),
            if (feed.loading && !feed.hasData)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: V13Skeleton.line(width: 220, height: 34),
              )
            else if (nudge != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: ArenaNudgeRow(nudge: nudge),
              ),
            if (feed.loading && !feed.hasData || nudge != null)
              const SizedBox(height: V13.gapSection),
            if (stats != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: V13StatTriple(
                  stats: [
                    V13Stat(label: 'Racing', value: stats.racing),
                    V13Stat(label: 'Wins', value: stats.wins),
                    V13Stat(label: 'Win rate', value: stats.winRate),
                  ],
                ),
              ),
              const SizedBox(height: V13.gapSection),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: ArenaActivitySection(
                days: arenaActivityDays(activity.valueOrNull ?? const {}),
                status: activity,
                onRetry: () => ref.invalidate(arenaActivityProvider),
              ),
            ),
            const SizedBox(height: V13.gapSection),
            if (progression.isLoading && !progression.hasValue)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: V13Skeleton.line(width: 200, height: 56),
              )
            else if (progression.hasError && !progression.hasValue)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: ArenaSectionError(
                  message: 'Couldn’t load achievements',
                  onRetry: () => ref
                      .read(progressionControllerProvider.notifier)
                      .load(force: true),
                ),
              )
            else if (progressionValue != null &&
                progressionValue.achievementsTotal > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: ArenaAchievementsSection(
                  progression: progressionValue,
                  tiles: arenaBadgeSlots(
                    progressionValue,
                    badgeCollection.valueOrNull ?? const [],
                  ),
                  onOpenBadges: () => context.push('/profile/badges'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _racesSection(RaceState raceState, List<ArenaCardData> cards) {
    if (raceState.loading && !raceState.hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
        child: V13Skeleton.box(
          width: double.infinity,
          height: ArenaRaceSwiper.height,
        ),
      );
    }
    if (raceState.error != null && !raceState.hasData) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
        child: ArenaSectionError(
          message: 'Couldn’t load your races',
          onRetry: () =>
              ref.read(raceControllerProvider.notifier).loadRaces(force: true),
        ),
      );
    }
    return ArenaRaceSwiper(
      cards: cards,
      plusBursts: _plusBursts,
      onPlusDone: _clearBurst,
    );
  }
}
