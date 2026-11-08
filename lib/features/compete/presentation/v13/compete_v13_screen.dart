import '../../../onboarding/presentation/first_use_guide.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/v13/v13.dart';
import '../../../notifications/domain/notification_display.dart';
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
    // The pre-v13 first-race coach tour pointed at the old composer, which no
    // longer exists. A new account still lands here (auth_gate routes the
    // first run to /compete) where "New race" is the obvious next step, so
    // any composer-era guide step is retired — persisted per account, which
    // also lets later launches open on Arena.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final step = ref.read(firstRaceGuideProvider);
      const retired = {
        FirstRaceGuideStep.competeStart,
        FirstRaceGuideStep.composerName,
        FirstRaceGuideStep.composerActivity,
        FirstRaceGuideStep.composerGoal,
        FirstRaceGuideStep.composerRacers,
        FirstRaceGuideStep.composerReview,
        FirstRaceGuideStep.raceDetail,
      };
      if (retired.contains(step)) completeFirstRaceGuide(ref);
    });
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
                  V13TabBar.bottomPadding(context),
                ),
                children: [
                  _Header(
                    firstName: _firstName(user?.fullName),
                    summary: _summary(live, user?.id),
                    onNewRace: () => context.push('/races/new'),
                    onJoinCode: () => context.push('/races/join'),
                    focus: _YouRightNow.pick(live, user?.id) == null
                        ? null
                        : _YouRightNow(
                            race: _YouRightNow.pick(live, user?.id)!,
                            userId: user!.id,
                          ),
                  ),
                  const SizedBox(height: V13.gapSection),
                  if (live.isNotEmpty) ...[
                    const _SectionHead('Live races'),
                    const SizedBox(height: V13.gapLg),
                    // Cards size to their content; the strip keeps room
                    // below/right for the 4pt hard shadow so it never clips.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(bottom: 6, right: 6),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < live.length; i++) ...[
                              if (i > 0) const SizedBox(width: V13.gapMd),
                              V13StaggerIn(
                                key: ValueKey('live-${live[i].id}'),
                                index: i,
                                child: _LiveRaceCard(
                                  race: live[i],
                                  userId: user?.id,
                                  onOpen: () =>
                                      context.push('/race/${live[i].id}'),
                                ),
                              ),
                            ],
                          ],
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
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onNewRace,
    required this.onJoinCode,
    this.focus,
    this.firstName,
    this.summary,
  });
  final VoidCallback onNewRace;
  final VoidCallback onJoinCode;

  /// "You right now" — the one race that most needs you. Optional.
  final Widget? focus;
  final String? firstName;

  /// One line of state: "2 live · 1 chasing you".
  final String? summary;

  @override
  Widget build(BuildContext context) {
    // One calm composition, content first: greeting + state line, the focus
    // strip when there's a contest, then the coloured Start hero with the
    // code link inside it. No floating actions, no blank band.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          firstName == null ? 'Compete' : 'Ready, $firstName?',
          style: V13.title,
        ),
        if (summary != null) ...[
          const SizedBox(height: 2),
          Text(summary!, style: V13.body.copyWith(color: V13.muted)),
        ],
        const SizedBox(height: V13.gapLg),
        if (focus != null) ...[focus!, const SizedBox(height: V13.gapMd)],
        V13Card(
          color: V13.blue,
          shadow: V13.shadow6,
          onTap: onNewRace,
          semanticLabel: 'Start a race',
          padding: const EdgeInsets.all(V13.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Start a race',
                      style: V13.cardTitle.copyWith(color: V13.card),
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: V13.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: V13.navy, width: V13.outline),
                    ),
                    child: const Icon(Icons.flag_rounded, color: V13.navy),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Pick a move, set the rules, invite friends.',
                style: V13.body.copyWith(
                  color: V13.card.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: V13.gapMd),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onJoinCode,
                child: Row(
                  children: [
                    Icon(
                      Icons.vpn_key_rounded,
                      size: 16,
                      color: V13.card.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Have a code? Join with a code',
                        style: V13.bodyStrong.copyWith(
                          color: V13.card,
                          decoration: TextDecoration.underline,
                          decorationColor: V13.card,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
    final hasTarget = raceHasFinishLine(race);
    final trend = rank != null && prevRank != null && prevRank != rank
        ? (rank < prevRank
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded)
        : null;

    return V13Card(
      onTap: onOpen,
      semanticLabel: 'Open ${race.displayTitle}',
      padding: EdgeInsets.zero,
      // Clip to the card's inner radius so the colored cap follows the
      // rounded corners instead of poking past them.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(V13.radiusCard - V13.outline),
        child: SizedBox(
          width: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  // The race's own base colour, not always coral.
                  color: V13.raceColor(race.id),
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
                      // Only races with a finish number get a progress bar —
                      // a most-total race has no 100%, so show the tally.
                      if (hasTarget) ...[
                        V13ProgressBar(value: progress),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        me == null
                            ? 'Not on the board yet'
                            : hasTarget
                            ? '${raceProgressLabel(race, me)} · ${(progress * 100).round()}%'
                            : '${raceProgressLabel(race, me)} · ${raceModeLabel(race.format)}',
                        style: V13.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: V13.gapMd),
                      // Pushes the faces to the bottom when a neighbour card
                      // is taller (IntrinsicHeight equalises the row).
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
      ),
    );
  }
}

class _OpenRacesSection extends ConsumerStatefulWidget {
  const _OpenRacesSection({
    required this.joinedIds,
    required this.joiningId,
    required this.onJoin,
  });
  final Set<String> joinedIds;
  final String? joiningId;
  final void Function(Race race) onJoin;

  @override
  ConsumerState<_OpenRacesSection> createState() => _OpenRacesSectionState();
}

/// "Join a race" as an activity list (Instagram-notifications style): open
/// rows with thin dividers, one bold line per person, a muted meta line and
/// a small filled Join pill. One person's several races collapse into a
/// single "Eswar is racing 3 races" row that expands in place.
class _OpenRacesSectionState extends ConsumerState<_OpenRacesSection> {
  final Set<String> _expanded = {};

  static RaceParticipant? _host(Race r) =>
      r.participantFor(r.creatorId) ?? r.participants.firstOrNull;

  @override
  Widget build(BuildContext context) {
    final races = ref.watch(openRacesProvider).valueOrNull;
    // Hidden on error or empty — the section is opportunistic, not required.
    if (races == null || races.isEmpty) return const SizedBox.shrink();

    // Group by host, keeping first-seen order.
    final groups = <String, List<Race>>{};
    for (final r in races) {
      groups.putIfAbsent(_host(r)?.userId ?? r.creatorId, () => []).add(r);
    }
    final keys = groups.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead('Join a race'),
        const SizedBox(height: V13.gapSm),
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const V13Divider(),
          V13StaggerIn(
            key: ValueKey('open-group-${keys[i]}'),
            index: i,
            child: _group(groups[keys[i]]!, keys[i]),
          ),
        ],
        const SizedBox(height: V13.gapSection),
      ],
    );
  }

  Widget _group(List<Race> races, String key) {
    final host = _host(races.first);
    final name = (host?.displayName ?? 'A friend')
        .trim()
        .split(RegExp(r'\s+'))
        .first;
    if (races.length == 1) {
      return _row(
        face: host,
        boldName: name,
        rest: ' is racing ${races.first.displayTitle}',
        meta: _meta(races.first),
        trailing: _joinPill(races.first),
      );
    }
    final open = _expanded.contains(key);
    return Column(
      children: [
        _row(
          face: host,
          boldName: name,
          rest: ' is racing ${races.length} races',
          meta: races.map((r) => r.displayTitle).take(2).join(' · '),
          trailing: AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: V13Motion.fast,
            curve: V13Motion.spring,
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: V13.muted,
            ),
          ),
          onTap: () => setState(() {
            open ? _expanded.remove(key) : _expanded.add(key);
          }),
        ),
        AnimatedSize(
          duration: V13Motion.fast,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child: Column(
                    children: [
                      for (final r in races)
                        _row(
                          boldName: r.displayTitle,
                          rest: '',
                          meta: _meta(r),
                          trailing: _joinPill(r),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  String _meta(Race r) {
    final n = r.participants.length;
    final created = DateTime.tryParse(r.createdAt);
    final when = created == null
        ? null
        : notificationRelativeTime(created.toUtc());
    return [
      '$n ${n == 1 ? 'racer' : 'racers'}',
      if (when != null) when,
    ].join(' · ');
  }

  Widget _row({
    RaceParticipant? face,
    required String boldName,
    required String rest,
    required String meta,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
      child: Row(
        children: [
          if (face != null) ...[
            V13Face(
              photoUrl: face.profilePhotoUrl,
              size: 40,
              name: face.displayName,
            ),
            const SizedBox(width: V13.gapMd),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: boldName, style: V13.bodyStrong),
                      TextSpan(text: rest, style: V13.body),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: V13.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: V13.gapMd),
          trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }

  Widget _joinPill(Race race) {
    final joined = widget.joinedIds.contains(race.id);
    final joining = widget.joiningId == race.id;
    return V13Pressable(
      onTap: joined || joining ? null : () => widget.onJoin(race),
      shadow: joined ? null : V13.shadow3,
      borderRadius: BorderRadius.circular(V13.radiusPill),
      semanticLabel: joined ? 'Joined' : 'Join ${race.displayTitle}',
      child: AnimatedContainer(
        duration: V13Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: joined ? V13.card : V13.blue,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: joining
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: V13.card,
                ),
              )
            : Text(
                joined ? 'Joined' : 'Join',
                style: V13.bodyStrong.copyWith(
                  color: joined ? V13.navy : V13.card,
                  fontSize: 14,
                ),
              ),
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
    // A board where everyone sits on 0 is noise ("#1 … #1, 0 pts"): hide it
    // until somebody scores.
    if (rows.every((r) => r.points <= 0)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHead('Leaderboard'),
        const SizedBox(height: V13.gapMd),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const V13Divider(),
          _LeaderboardRow(
            entry: rows[i],
            tied: rows.where((r) => r.rank == rows[i].rank).length > 1,
          ),
        ],
        const SizedBox(height: V13.gapSection),
      ],
    );
  }
}

class _LeaderboardRow extends ConsumerWidget {
  const _LeaderboardRow({required this.entry, this.tied = false});
  final LeaderboardEntry entry;

  /// Shares its rank with another row — shown as "=2" instead of "#2".
  final bool tied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = V13ListRow(
      title: entry.isMe ? 'You' : entry.displayName,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${tied ? '=' : '#'}${entry.rank}',
              style: V13.numberSm,
            ),
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
          V13StaggerIn(
            key: ValueKey('move-${moves[i].activity.activityId}'),
            index: i,
            child: V13ListRow(
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
                    color: V13.card,
                    borderRadius: BorderRadius.circular(V13.radiusPill),
                    border: Border.all(color: V13.navy, width: V13.outline),
                  ),
                  child: Text(
                    'Start',
                    style: V13.label.copyWith(color: V13.navy),
                  ),
                ),
              ),
              showDivider: false,
            ),
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

/// Compete's single focal strip: your standing in the race that most needs
/// you — the closest contest with someone to chase or defend against, ties
/// broken by the soonest finish line. One tap opens that race.
class _YouRightNow extends StatelessWidget {
  const _YouRightNow({required this.race, required this.userId});

  final Race race;
  final String userId;

  static Race? pick(List<Race> live, String? userId) {
    if (userId == null) return null;
    Race? best;
    var bestScore = 1 << 30;
    for (final r in live) {
      if (r.participants.length < 2 || r.participantFor(userId) == null) {
        continue;
      }
      final c = ChaseContext.compute(r, userId);
      if (c.myRank == null || c.chaseCopy == null) continue;
      // Smaller is more urgent: close gaps first, then near deadlines.
      final gap = (c.leaderGap ?? 50).abs().clamp(0, 999);
      final days = (c.daysLeft ?? 30).clamp(0, 999);
      final score = gap * 10 + days;
      if (score < bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final c = ChaseContext.compute(race, userId);
    return V13Card(
      onTap: () => context.push('/race/${race.id}'),
      semanticLabel: 'Open ${race.displayTitle}',
      padding: const EdgeInsets.all(V13.gapLg),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.myRank == 1 ? V13.sun : V13.sky,
              shape: BoxShape.circle,
              border: Border.all(color: V13.navy, width: V13.outline),
            ),
            child: Text('#${c.myRank}', style: V13.numberSm),
          ),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOU RIGHT NOW', style: V13.label),
                const SizedBox(height: 2),
                Text(
                  race.displayTitle,
                  style: V13.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  c.chaseCopy!,
                  style: V13.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (c.timeLeft != null) ...[
            const SizedBox(width: V13.gapSm),
            V13Pill(label: c.timeLeft!, color: V13.sun, textColor: V13.navy),
          ],
          const SizedBox(width: V13.gapXs),
          const Icon(Icons.chevron_right_rounded, color: V13.muted),
        ],
      ),
    );
  }
}

String? _firstName(String? full) {
  final f = full?.trim().split(RegExp(r'\s+')).first ?? '';
  return f.isEmpty ? null : f;
}

/// "2 live · 1 chasing you" — counts from the races already on screen.
String? _summary(List<Race> live, String? userId) {
  if (live.isEmpty) return 'No live races yet \u2014 start one.';
  var chased = 0;
  if (userId != null) {
    for (final r in live) {
      if (r.participants.length > 1 && rankForUser(r, userId) == 1) chased++;
    }
  }
  return [
    '${live.length} live',
    if (chased > 0) '$chased chasing you',
  ].join(' \u00b7 ');
}
