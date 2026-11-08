import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/v13/v13.dart';
import '../../../races/data/race_models.dart';
import '../../../races/domain/chase_context.dart';
import '../../../races/domain/motion_activity.dart';
import '../../../races/domain/race_display.dart';
import '../../../races/domain/race_draft.dart';
import '../../../races/presentation/motion_catalog_provider.dart';
import '../../../races/presentation/race_controller.dart';
import '../../../auth/presentation/auth_controller.dart';

/// `GET /races/open` (W3) — friends' joinable races. The provider returns
/// null when the call fails (older Worker → 404): the section hides instead
/// of surfacing an error for a payload the app cannot do anything with.
final openRacesProvider = FutureProvider.autoDispose<List<Race>?>((ref) async {
  try {
    return await ref.read(raceRepositoryProvider).getOpenRaces();
  } catch (_) {
    return null;
  }
});

/// `GET /leaderboard?scope=friends` (W3) — weekly proof-points board.
/// Same contract: absent payload → hidden section, never an error card.
final friendsLeaderboardProvider =
    FutureProvider.autoDispose<List<LeaderboardEntry>?>((ref) async {
      try {
        return await ref
            .read(raceRepositoryProvider)
            .getLeaderboard(scope: 'friends');
      } catch (_) {
        return null;
      }
    });

/// Trending moves = catalog movements ordered by `racerCount` (W3) with
/// the four featured presets as the fallback when counts are absent.
final trendingMovesProvider = Provider.autoDispose<List<_TrendingMove>>((ref) {
  final snapshot = ref.watch(motionCatalogProvider).valueOrNull;
  final defs = availableMotionActivities(
    snapshot,
    ref.watch(motionCapabilitiesProvider),
  ).toList();
  final counts = {
    if (snapshot != null)
      for (final a in snapshot.activities)
        if (a.racerCount != null) a.id: a.racerCount!,
  };
  final ordered = [...defs]
    ..sort((a, b) {
      final ca = counts[a.activityId] ?? -1;
      final cb = counts[b.activityId] ?? -1;
      if (ca != cb) return cb.compareTo(ca);
      final fa = a.featured ? 0 : 1;
      final fb = b.featured ? 0 : 1;
      if (fa != fb) return fa.compareTo(fb);
      return a.title.compareTo(b.title);
    });
  return [
    for (final a in ordered.take(6)) _TrendingMove(a, counts[a.activityId]),
  ];
});

class _TrendingMove {
  const _TrendingMove(this.activity, this.racerCount);
  final MotionActivityDefinition activity;
  final int? racerCount;
}

/// v13 Compete tab — start or join a race. Header + live-race swipers,
/// open-race join cards, friends leaderboard, trending moves, trophies.
class CompeteV13Screen extends ConsumerStatefulWidget {
  const CompeteV13Screen({super.key});

  @override
  ConsumerState<CompeteV13Screen> createState() => _CompeteV13ScreenState();
}

class _CompeteV13ScreenState extends ConsumerState<CompeteV13Screen> {
  final _scroll = ScrollController();
  final _joinedIds = <String>{};
  bool _moreBelow = true;
  bool _joining = false;
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show =
          !_scroll.hasClients ||
          _scroll.position.maxScrollExtent <= 0 ||
          _scroll.offset < 40;
      if (show != _moreBelow) setState(() => _moreBelow = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    unawaited(ref.read(raceControllerProvider.notifier).loadRaces(force: true));
    ref.invalidate(openRacesProvider);
    ref.invalidate(friendsLeaderboardProvider);
  }

  Future<void> _joinOpenRace(Race race) async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _joiningId = race.id;
    });
    try {
      await ref.read(raceControllerProvider.notifier).joinRace(race.id);
      if (!mounted) return;
      setState(() => _joinedIds.add(race.id));
      showV13Confetti(context);
      showV13Toast(context, 'You\'re in. Good luck.');
    } catch (_) {
      if (mounted) showV13Toast(context, 'Could not join this race.');
    } finally {
      if (mounted) {
        setState(() {
          _joining = false;
          _joiningId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final raceState = ref.watch(raceControllerProvider);
    final races = raceState.races;
    final live = races.where(raceIsActive).toList();
    final finished = races.where(raceIsCompleted).toList();

    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refresh,
              color: V13.blue,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  V13.pagePad,
                  V13.gapMd,
                  V13.pagePad,
                  V13TabBar.bottomPadding(context) + 72,
                ),
                children: [
                  _Header(
                    onNewRace: () => context.push('/races/new'),
                    onJoinCode: () => context.push('/races/join'),
                  ),
                  const SizedBox(height: V13.gapSection),
                  if (live.isNotEmpty) ...[
                    const _SectionHead('Live races'),
                    const SizedBox(height: V13.gapLg),
                    SizedBox(
                      height: 250,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: live.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: V13.gapMd),
                        itemBuilder: (_, i) => _LiveRaceCard(
                          race: live[i],
                          userId: user?.id,
                          onOpen: () => context.push('/race/${live[i].id}'),
                        ),
                      ),
                    ),
                    const SizedBox(height: V13.gapSection),
                  ],
                  _OpenRacesSection(
                    joinedIds: _joinedIds,
                    joiningId: _joiningId,
                    onJoin: _joinOpenRace,
                  ),
                  const _LeaderboardSection(),
                  _TrendingSection(
                    onStart: (a) => context.push(
                      '/races/new',
                      extra: RaceCreatePrefill(draft: draftForActivity(a)),
                    ),
                  ),
                  if (finished.isNotEmpty) ...[
                    const _SectionHead('Trophy shelf'),
                    const SizedBox(height: V13.gapLg),
                    _TrophyShelf(races: finished, userId: user?.id),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: V13TabBar.bottomPadding(context) + 12,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _moreBelow ? 1 : 0,
                  duration: V13Motion.fast,
                  child: const Center(
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: V13.muted,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNewRace, required this.onJoinCode});
  final VoidCallback onNewRace;
  final VoidCallback onJoinCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Compete', style: V13.title),
        const SizedBox(height: V13.gapLg),
        Row(
          children: [
            Expanded(
              child: V13Button.primary(
                label: 'New race',
                icon: Icons.flag_rounded,
                onPressed: onNewRace,
              ),
            ),
          ],
        ),
        const SizedBox(height: V13.gapMd),
        V13Pressable(
          onTap: onJoinCode,
          pressDepth: 1.5,
          semanticLabel: 'Join with a code',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Join with a code',
              style: V13.bodyStrong.copyWith(color: V13.blue),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: V13.sectionHead);
}

class _LiveRaceCard extends ConsumerWidget {
  const _LiveRaceCard({
    required this.race,
    required this.userId,
    required this.onOpen,
  });
  final Race race;
  final String? userId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chase = userId == null ? null : ChaseContext.compute(race, userId!);
    final sorted = serverRankedParticipants(race);
    final rank = rankForUser(race, userId);
    final prevRank = race.viewerContext?.previousRank;
    final me = userId == null ? null : race.participantFor(userId!);
    final progress = raceProgressPercent(race, me) / 100;
    final trend = rank != null && prevRank != null && prevRank != rank
        ? (rank < prevRank
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded)
        : null;

    return V13Card(
      onTap: onOpen,
      semanticLabel: 'Open ${race.displayTitle}',
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 250,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 8,
              decoration: const BoxDecoration(
                color: V13.coral,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(V13.radiusCard - 3),
                ),
                border: Border(
                  bottom: BorderSide(color: V13.navy, width: V13.outline),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(V13.gapMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            race.displayTitle,
                            style: V13.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chase?.timeLeft != null)
                          V13Pill(
                            label: chase!.timeLeft!,
                            color: V13.sun,
                            textColor: V13.navy,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (rank != null) Text('#$rank', style: V13.numberSm),
                        if (trend != null) ...[
                          const SizedBox(width: 2),
                          Icon(trend, size: 18, color: V13.blue),
                        ],
                        const SizedBox(width: V13.gapSm),
                        Expanded(
                          child: Text(
                            '${sorted.length} racer${sorted.length == 1 ? '' : 's'}',
                            style: V13.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: V13.gapMd),
                    V13ProgressBar(value: progress),
                    const SizedBox(height: 4),
                    Text(
                      me == null
                          ? 'Not on the board yet'
                          : '${raceProgressLabel(race, me)} · ${(progress * 100).round()}%',
                      style: V13.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        V13FaceStack(
                          faces: [
                            for (final p in sorted.take(4))
                              V13FaceInfo(
                                photoUrl: p.profilePhotoUrl,
                                name: p.displayName,
                                isMe: p.userId == userId,
                              ),
                          ],
                          size: 22,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenRacesSection extends ConsumerWidget {
  const _OpenRacesSection({
    required this.joinedIds,
    required this.joiningId,
    required this.onJoin,
  });
  final Set<String> joinedIds;
  final String? joiningId;
  final void Function(Race race) onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(openRacesProvider);
    final races = value.valueOrNull;
    // Hidden on error or empty — the section is opportunistic, not required.
    if (races == null || races.isEmpty) return const SizedBox.shrink();
    final visible = races.where((r) => !joinedIds.contains(r.id)).toList();
    final joinedVisible = races.where((r) => joinedIds.contains(r.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead('Join a race'),
        const SizedBox(height: V13.gapLg),
        for (final race in [...visible, ...joinedVisible]) ...[
          _OpenRaceCard(
            race: race,
            joined: joinedIds.contains(race.id),
            joining: joiningId == race.id,
            onJoin: () => onJoin(race),
          ),
          const SizedBox(height: V13.gapMd),
        ],
        const SizedBox(height: V13.gapSection - V13.gapMd),
      ],
    );
  }
}

class _OpenRaceCard extends StatelessWidget {
  const _OpenRaceCard({
    required this.race,
    required this.joined,
    required this.joining,
    required this.onJoin,
  });
  final Race race;
  final bool joined;
  final bool joining;
  final VoidCallback onJoin;

  String _namesLine() {
    final names = race.participants
        .take(3)
        .map((p) => p.displayName.trim().split(RegExp(r'\s+')).first)
        .toList();
    if (names.isEmpty) return 'Your friends are racing';
    if (names.length == 1) return '${names[0]} is racing';
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    return '${names[0]}, ${names[1]} and ${names[2]}';
  }

  @override
  Widget build(BuildContext context) {
    return V13Card(
      padding: const EdgeInsets.all(V13.gapMd),
      child: Row(
        children: [
          V13FaceStack(
            faces: [
              for (final p in race.participants.take(3))
                V13FaceInfo(photoUrl: p.profilePhotoUrl, name: p.displayName),
            ],
            size: 30,
          ),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _namesLine(),
                  style: V13.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  race.displayTitle,
                  style: V13.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: V13.gapMd),
          V13Button.secondary(
            label: joined ? 'Joined' : 'Join',
            onPressed: joined ? null : onJoin,
            loading: joining,
            icon: joined ? Icons.check_rounded : null,
          ),
        ],
      ),
    );
  }
}

class _LeaderboardSection extends ConsumerWidget {
  const _LeaderboardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(friendsLeaderboardProvider).valueOrNull;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead('Leaderboard'),
        const SizedBox(height: V13.gapMd),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const V13Divider(),
          _LeaderboardRow(entry: rows[i]),
        ],
        const SizedBox(height: V13.gapSection),
      ],
    );
  }
}

class _LeaderboardRow extends ConsumerWidget {
  const _LeaderboardRow({required this.entry});
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = V13ListRow(
      title: entry.isMe ? 'You' : entry.displayName,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            child: Text('#${entry.rank}', style: V13.numberSm),
          ),
          V13Face(
            photoUrl: entry.profilePhotoUrl,
            size: 34,
            isMe: entry.isMe,
            name: entry.displayName,
          ),
        ],
      ),
      trailing: Text('${entry.points} pts', style: V13.bodyStrong),
      onTap: () => openPerson(context, ref, entry.userId),
      showDivider: false,
      padding: EdgeInsets.symmetric(
        horizontal: entry.isMe ? V13.gapSm : 0,
        vertical: V13.gapSm,
      ),
    );
    if (!entry.isMe) return row;
    return Container(
      decoration: BoxDecoration(
        color: V13.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(V13.radiusCard),
      ),
      child: row,
    );
  }
}

class _TrendingSection extends ConsumerWidget {
  const _TrendingSection({required this.onStart});
  final void Function(MotionActivityDefinition activity) onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moves = ref.watch(trendingMovesProvider);
    if (moves.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead('Trending moves'),
        const SizedBox(height: V13.gapMd),
        for (var i = 0; i < moves.length; i++) ...[
          if (i > 0) const V13Divider(),
          V13ListRow(
            title: moves[i].activity.title,
            subtitle: moves[i].racerCount != null
                ? '${moves[i].racerCount} racing'
                : null,
            leading: V13IconTile(
              icon: moves[i].activity.icon,
              color: const [
                V13.coral,
                V13.sun,
                V13.mint,
                V13.sky,
                V13.lilac,
              ][i % 5],
            ),
            trailing: V13Pressable(
              onTap: () => onStart(moves[i].activity),
              pressDepth: 1.5,
              semanticLabel: 'Start a ${moves[i].activity.title} race',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: V13.blue,
                  borderRadius: BorderRadius.circular(V13.radiusPill),
                  border: Border.all(color: V13.navy, width: V13.outline),
                ),
                child: Text(
                  'Start',
                  style: V13.label.copyWith(color: V13.card),
                ),
              ),
            ),
            showDivider: false,
          ),
        ],
        const SizedBox(height: V13.gapSection),
      ],
    );
  }
}

class _TrophyShelf extends StatelessWidget {
  const _TrophyShelf({required this.races, required this.userId});
  final List<Race> races;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final recent = races.take(6).toList();
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recent.length,
        separatorBuilder: (_, _) => const SizedBox(width: V13.gapMd),
        itemBuilder: (_, i) {
          final race = recent[i];
          final rank = _finalRank(race);
          return V13Pressable(
            onTap: () => context.push('/race/${race.id}'),
            pressDepth: 2,
            semanticLabel: 'Open ${race.displayTitle}',
            child: SizedBox(
              width: 92,
              child: Column(
                children: [
                  V13MedalCircle(place: rank ?? 0, size: 56),
                  const SizedBox(height: V13.gapSm),
                  Text(
                    race.displayTitle,
                    style: V13.caption,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  int? _finalRank(Race race) {
    if (userId == null) return null;
    for (final s in race.finalStandings) {
      if (s.userId == userId) return s.rank;
    }
    return rankForUser(race, userId);
  }
}
