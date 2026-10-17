import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/nuvo_flags.dart';
import '../../../core/demo/presentation_demo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/live_refresh.dart';
import '../../../core/widgets/sliver_fold_guard.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_flip_card.dart';
import '../../../core/widgets/nuvo_live_race_card.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_ripple_surface.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../../core/widgets/nuvo_race_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/nuvo_stagger_in.dart';
import '../../../data/models/user_profile.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../application/member_pass_provider.dart';
import '../../crew/application/crew_controller.dart';
import '../../crew/data/crew_api.dart'
    show ConnectOutcome, CrewConnectionStatus, CrewSearchResult;
import '../../crew/domain/crew_presence.dart';
import '../../notifications/application/notification_controller.dart';
import '../../notifications/domain/notification_display.dart';
import '../../notifications/presentation/notification_bell.dart';

import '../../social/data/crew_activity.dart';
import '../../social/domain/nuvo_destination.dart';
import '../../social/presentation/theme_ink.dart';
import 'package:go_router/go_router.dart';

class PassScreen extends ConsumerStatefulWidget {
  const PassScreen({super.key});

  @override
  ConsumerState<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends ConsumerState<PassScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<CrewSearchResult> _results = const [];
  bool _searching = false;
  bool _searchOpen = false;
  String? _searchError;

  /// Crew lenses: 0 People · 1 Activity.
  int _feedTab = 0;

  /// Post CTAs in flight (join/rematch) — freezes the chip so a second tap
  /// can't race the in-flight mutation.
  final _ctaBusy = <String>{};

  @override
  void initState() {
    super.initState();
    // Crew reads shared races off RaceController's cache — kick its
    // revalidation after the first frame (providers can't be touched
    // mid-lifecycle) so Racing Together/Right Now never sit stale.
    Future(() => ref.read(raceControllerProvider.notifier).revalidate());
    Future.microtask(
      () => ref.read(memberPassProvider.notifier).ensureLoaded(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// The member pass is owned by [memberPassProvider] (loaded once per
  /// account, cached on disk); this is the explicit refresh.
  Future<void> _fetch() => ref.read(memberPassProvider.notifier).refresh();

  /// Pull-to-refresh revalidates everything the page reads — the member pass
  /// plus the canonical crew + notification controllers — not just the pass.
  Future<void> _refreshAll() async {
    await Future.wait([
      _fetch(),
      ref.read(crewControllerProvider.notifier).load(force: true),
      ref.read(notificationControllerProvider.notifier).load(force: true),
      ref.read(crewActivityProvider.notifier).load(force: true),
    ]);
  }

  UserProfile _buildProfile(AuthUser? user) {
    return UserProfile(
      name: user?.fullName ?? user?.email ?? '',
      username: user?.username ?? '',
      memberId: ref.read(memberPassProvider).info?.memberId ?? '-',
      passSlug: ref.read(memberPassProvider).info?.passSlug,
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        // CrewController.search returns per-user connection status and merges
        // it into the shared relationship map — one source of truth for
        // Add / Requested / Accept / In crew across search, requests and list.
        final results = await ref
            .read(crewControllerProvider.notifier)
            .search(query);
        if (mounted) {
          setState(() {
            _results = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _searching = false;
            _searchError = 'Search failed. Try again.';
          });
        }
      }
    });
  }

  Future<void> _addCrew(PublicUser user) async {
    try {
      final outcome = await ref.read(crewControllerProvider.notifier).add(user);
      if (mounted && outcome == ConnectOutcome.pending) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request sent.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add this friend.')),
        );
      }
    }
  }

  Future<void> _acceptRequest(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).acceptRequest(user);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't accept the request.")),
        );
      }
    }
  }

  Future<void> _declineRequest(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).declineRequest(user);
    } catch (_) {
      /* best-effort */
    }
  }

  Future<void> _cancelRequest(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).remove(user.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't cancel the request.")),
        );
      }
    }
  }

  void _openCrewActivity(CrewActivityItem item) {
    final destination = item.destination;
    if (destination == null) return;
    // Notification-sourced items ('ntf:' ids) mark their inbox row read —
    // canonical event items have no read state to clear.
    if (item.id.startsWith('ntf:')) {
      ref
          .read(notificationControllerProvider.notifier)
          .markRead(item.id.substring(4));
    }
    context.push(destination.location);
  }

  Future<void> _react(CrewActivityItem item, String emoji) async {
    HapticFeedback.selectionClick();
    final ok = await ref
        .read(crewActivityProvider.notifier)
        .toggleReaction(item, emoji);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't send that reaction.")),
      );
    }
  }

  /// Resolve a feed actor to a PublicUser — the crew roster when they're
  /// connected (full presence/handle), else a minimal card from the actor
  /// fields the feed carries.
  PublicUser _personFor(CrewActivityActor actor, List<PublicUser> crew) {
    for (final m in crew) {
      if (m.id == actor.id) return m;
    }
    final parts = actor.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    return PublicUser(
      id: actor.id,
      displayName: actor.displayName,
      initials: parts.isEmpty
          ? 'N'
          : parts.length == 1
          ? parts.first[0].toUpperCase()
          : '${parts.first[0]}${parts.last[0]}'.toUpperCase(),
      profilePhotoUrl: actor.profilePhotoUrl,
    );
  }

  /// The lightweight social surface — a person, not a profile page: who
  /// they are to me (races together, head-to-head), the two real actions,
  /// and the last few mutual results.
  void _openPerson(PublicUser member) {
    final myId = ref.read(authControllerProvider).user?.id ?? '';
    final shared = ref
        .read(raceControllerProvider)
        .races
        .where((r) => r.isParticipant(member.id) && r.isParticipant(myId))
        .toList();
    // If they're inside an active shared race right now, the sheet leads
    // with it — "Racing now · Pushup Battle" opens the race room.
    final racingIn = shared.where((r) => r.status == 'active').firstOrNull;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.themeColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _PersonSheet(
        member: member,
        myId: myId,
        myInitials: ref.read(authControllerProvider).user?.avatarInitials,
        myPhotoUrl: ref.read(authControllerProvider).user?.profilePhotoUrl,
        sharedRaces: shared,
        racingIn: racingIn,
        onRace: () {
          Navigator.of(sheetContext).pop();
          context.push(
            '/races/new',
            extra: RaceCreatePrefill.pushups.copyWith(withUser: member),
          );
        },
        onProfile: () {
          Navigator.of(sheetContext).pop();
          context.push('/u/${member.id}');
        },
        onWatch: racingIn == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                context.push('/race/${racingIn.id}');
              },
      ),
    );
  }

  void _tapFeedPerson(CrewActivityItem item, List<PublicUser> crew) {
    final actor = item.actor;
    if (actor == null || actor.id.isEmpty) {
      _openCrewActivity(item);
      return;
    }
    final myId = ref.read(authControllerProvider).user?.id ?? '';
    if (actor.id == myId) {
      _openCrewActivity(item);
      return;
    }
    _openPerson(_personFor(actor, crew));
  }

  /// The social CTA a post earns — resolved against live race state, not
  /// the event text: an overtake offers Take it back while the race runs
  /// and Rematch once it's settled.
  _PostAction? _actionFor(
    CrewActivityItem item,
    String myId,
    Map<String, Race> racesById,
  ) {
    final race = racesById[item.raceId];
    final completed = race?.status == 'completed';
    final member = race?.isParticipant(myId) ?? false;
    final first = item.actor?.displayName.split(' ').first ?? '';
    switch (item.type) {
      case 'rank_changed':
        final overtaken = item.payload['overtakenUserIds'];
        if (overtaken is! List || !overtaken.contains(myId)) return null;
        if (completed) {
          return _PostAction(label: 'Rematch', onTap: () => _rematch(item));
        }
        return _PostAction(
          label: 'Take it back',
          onTap: () => _openCrewActivity(item),
        );
      case 'lead_changed':
        if (item.payload['displacedUserId'] != myId) return null;
        return _PostAction(
          label: 'Take it back',
          onTap: () => _openCrewActivity(item),
        );
      case 'participant_finished':
        if (completed && member) {
          return _PostAction(
            label: first.isEmpty ? 'Rematch' : 'Rematch $first',
            onTap: () => _rematch(item),
          );
        }
        if (member) {
          return _PostAction(
            label: 'Open race',
            onTap: () => _openCrewActivity(item),
          );
        }
        return null;
      case 'race_finished':
      case 'winner_determined':
        if (!member) return null;
        return _PostAction(label: 'Rematch', onTap: () => _rematch(item));
      case 'personal_best':
        final actor = item.actor;
        if (actor == null || actor.id == myId) return null;
        return _PostAction(
          label: 'Race $first',
          onTap: () => context.push(
            '/races/new',
            extra: RaceCreatePrefill.pushups.copyWith(
              withUser: _personFor(
                actor,
                ref.read(crewControllerProvider).members,
              ),
            ),
          ),
        );
      case 'race_created':
        final actor = item.actor;
        if (actor == null || actor.id == myId) return null;
        if (member) {
          return _PostAction(
            label: 'Open race',
            onTap: () => _openCrewActivity(item),
          );
        }
        return _PostAction(label: 'Join race', onTap: () => _joinRace(item));
      case 'race_invite':
        return _PostAction(label: 'Join race', onTap: () => _joinRace(item));
      case 'race_started':
        if (!member) return null;
        return _PostAction(
          label: 'Open race',
          onTap: () => _openCrewActivity(item),
        );
      case 'rematch_requested':
        final rematchId = item.payload['rematchRaceId'] as String?;
        if (rematchId != null && rematchId.isNotEmpty) {
          return _PostAction(
            label: 'Join rematch',
            onTap: () => _joinRace(item, raceId: rematchId),
          );
        }
        return null;
      default:
        return null;
    }
  }

  Future<void> _joinRace(CrewActivityItem item, {String? raceId}) async {
    final id =
        raceId ??
        item.raceId ??
        (item.destination is RaceDestination
            ? (item.destination as RaceDestination).raceId
            : null);
    if (id == null || !_ctaBusy.add(item.id)) return;
    try {
      final race = await ref.read(raceControllerProvider.notifier).joinRace(id);
      if (mounted) context.push('/race/${race.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't join that race.")),
        );
      }
    } finally {
      if (mounted) setState(() => _ctaBusy.remove(item.id));
    }
  }

  Future<void> _rematch(CrewActivityItem item) async {
    final id = item.raceId;
    if (id == null || !_ctaBusy.add(item.id)) return;
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .rematchRace(id);
      if (mounted) context.push('/race/${race.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start the rematch.")),
        );
      }
    } finally {
      if (mounted) setState(() => _ctaBusy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider).user;
    final user = authUser == null ? null : presentedUser(authUser);
    final pass = ref.watch(memberPassProvider);
    final passLoading = pass.loading && pass.info == null;
    if (passLoading) {
      // The provider is rebuilt on an account change; (re)start its one load.
      // ensureLoaded is idempotent, so repeat builds don't refetch.
      Future.microtask(() {
        if (mounted) ref.read(memberPassProvider.notifier).ensureLoaded();
      });
    }
    final passError = pass.failed && pass.info == null
        ? 'Could not load your friends.'
        : null;
    final profile = _buildProfile(user);
    final crewState = ref.watch(crewControllerProvider);
    final crew = crewState.members;
    final requests = crewState.requests;
    final outgoing = crewState.outgoing;
    final pending = crewState.pendingUserIds;
    final myId = authUser?.id ?? '';
    // Social activity — Crew's own typed projection (canonical race_events +
    // crew-lifecycle rows from GET /crew/feed), not the notification inbox.
    final activityState = ref.watch(crewActivityProvider);
    final feedItems = activityState.items.take(15).toList();
    // Races shared with crew — derived from RaceController's already-loaded
    // list (my races), no extra fetches.
    final crewIds = {for (final m in crew) m.id};
    final allRaces = ref.watch(raceControllerProvider).races;
    final racesById = {for (final r in allRaces) r.id: r};
    final sharedRaces =
        allRaces
            .where((r) => r.status == 'active' && crewIds.any(r.isParticipant))
            .toList()
          ..sort((a, b) {
            int crewCount(Race r) =>
                r.participants.where((p) => crewIds.contains(p.userId)).length;
            return crewCount(b).compareTo(crewCount(a));
          });
    // People's racing-now group — LIVE → ACTIVE — reads the same canonical truth as the feed: `race_live` items are the
    // server's live spectator payload (they also surface in For you), and
    // 'scheduled' is the server's effective status for a future start line.
    // A race already rendering as a live card is skipped from Active — one
    // race, one presentation.
    final liveItems = activityState.items.where((i) => i.live != null).toList();
    final liveRaceIds = {
      for (final i in liveItems)
        if (i.raceId != null) i.raceId!,
    };
    final activeRaces = sharedRaces
        .where((r) => !liveRaceIds.contains(r.id))
        .toList();
    // Racing beats Active — a member inside an active shared race gets the
    // "Racing" pill; presence alone gets "Active".
    final racingIds = <String>{
      for (final r in sharedRaces)
        for (final p in r.participants)
          if (crewIds.contains(p.userId)) p.userId,
    };
    // A member with a real achievement in the last day earns 🔥 — PBs,
    // finishes, wins. Grounded in the same feed items, nothing invented.
    final hotIds = <String>{
      for (final i in activityState.items)
        if (i.actor != null &&
            crewIds.contains(i.actor!.id) &&
            DateTime.now().toUtc().difference(i.occurredAt).inHours < 24 &&
            const {
              'personal_best',
              'participant_finished',
              'race_finished',
              'winner_determined',
            }.contains(i.type))
          i.actor!.id,
    };
    // Who's around right now — real presence only (server-touched
    // lastActiveAt), ordered most-recent first. The strip fronts the people
    // who are here.
    final now = DateTime.now().toUtc();
    final liveCrew =
        crew
            .where(
              (m) =>
                  crewPresenceFor(m.lastActiveAt, now: now) ==
                      CrewPresence.active ||
                  crewPresenceFor(m.lastActiveAt, now: now) ==
                      CrewPresence.recentlyActive,
            )
            .toList()
          ..sort(
            (a, b) => (b.lastActiveAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  a.lastActiveAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
          );
    final crewOrdered = [
      ...liveCrew,
      ...crew.where((m) => liveCrew.every((l) => l.id != m.id)),
    ];
    return LiveRefresh(
      onRefresh: () => unawaited(_refreshAll()),
      child: Scaffold(
      backgroundColor: context.themeColors.page,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: RefreshIndicator(
                onRefresh: _refreshAll,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    // Horizontal inset moves inside the sections — the social
                    // field bleeds edge-to-edge while content keeps the 20 inset.
                    SliverFoldFit(
                      foldInset: NuvoBottomNav.bottomPadding(context) - 10,
                      enabled:
                          _feedTab == 0 &&
                          !passLoading &&
                          passError == null &&
                          !_searchOpen,
                      children: [
                        const FoldGap(20),
                        // ── Header ───────────────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: NuvoSpacing.pageHorizontal,
                          ),
                          child: _CrewHeader(
                            subtitle: crew.isEmpty
                                ? 'Find people to race with.'
                                : 'Your people, all in one place',
                            onMyCode: () => context.push('/my-nuvo'),
                            searchOpen: _searchOpen,
                            onToggleSearch: () =>
                                setState(() => _searchOpen = !_searchOpen),
                          ),
                        ),

                        // ── Search expands inline from the header icon — a tool that
                        // opens when needed, not a section competing with the people.
                        if (_searchOpen) ...[
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NuvoSpacing.pageHorizontal,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: NuvoSearchField(
                                    controller: _searchController,
                                    hint: 'Username or member ID',
                                    searching: _searching,
                                    autofocus: true,
                                    onChanged: _onSearchChanged,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _ScanButton(onTap: () => context.push('/scan')),
                              ],
                            ),
                          ),
                          if (_results.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NuvoSpacing.pageHorizontal,
                              ),
                              child: _SearchResultList(
                                results: _results,
                                crewState: crewState,
                                onAdd: _addCrew,
                                onAccept: _acceptRequest,
                              ),
                            ),
                          ] else if (_searchError != null && !_searching) ...[
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NuvoSpacing.pageHorizontal,
                              ),
                              child: NuvoPressable(
                                onTap: () =>
                                    _onSearchChanged(_searchController.text),
                                haptic: false,
                                child: _EmptyNote(text: _searchError!),
                              ),
                            ),
                          ] else if (_searchController.text.trim().length >=
                                  2 &&
                              !_searching) ...[
                            const SizedBox(height: 16),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: NuvoSpacing.pageHorizontal,
                              ),
                              child: _EmptyNote(
                                text: 'No matching Nuvo members found.',
                              ),
                            ),
                          ],
                        ],
                        const FoldGap(14),

                        // ── Loading ──────────────────────────────────────────────────
                        if (passLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: NuvoSpacing.pageHorizontal,
                            ),
                            child: _CrewSkeleton(),
                          )
                        // ── Error ────────────────────────────────────────────────────
                        else if (passError != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NuvoSpacing.pageHorizontal,
                            ),
                            child: NuvoErrorState(
                              message: passError,
                              onRetry: _refreshAll,
                            ),
                          )
                        // ── Content ──────────────────────────────────────────────────
                        else ...[
                          // The lens switch leads the page: People (who I race with and
                          // what we are racing right now) and Activity (what happened).
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NuvoSpacing.pageHorizontal,
                            ),
                            child: _CrewTabs(
                              selected: _feedTab,
                              onSelect: (i) => setState(() => _feedTab = i),
                              counts: [requests.length, null],
                            ),
                          ),
                          const FoldGap(16),

                          if (crewState.error != null && crew.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                NuvoSpacing.pageHorizontal,
                                0,
                                NuvoSpacing.pageHorizontal,
                                14,
                              ),
                              child: NuvoErrorState(
                                message: crewState.error!,
                                onRetry: () => ref
                                    .read(crewControllerProvider.notifier)
                                    .load(force: true),
                              ),
                            ),
                          if (activityState.error != null && feedItems.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                NuvoSpacing.pageHorizontal,
                                0,
                                NuvoSpacing.pageHorizontal,
                                14,
                              ),
                              child: NuvoErrorState(
                                message: activityState.error!,
                                onRetry: () => ref
                                    .read(crewActivityProvider.notifier)
                                    .load(force: true),
                              ),
                            ),

                          // ── People — the crews entry, the people, their asks, and
                          // the races running with them right now.
                          if (_feedTab == 0) ...[
                            _SocialField(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Race together on one leaderboard — start or join a
                                  // crew. Only when the server has crews switched on.
                                  ValueListenableBuilder<bool>(
                                    valueListenable: NuvoFlags.crews,
                                    builder: (context, crewsOn, _) => crewsOn
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 16,
                                            ),
                                            child: _PeopleSurface(
                                              children: [
                                                _ActionRow(
                                                  icon: Icons.groups_rounded,
                                                  leading: const NuvoCrewIcon(
                                                    size: 26,
                                                    semanticLabel: null,
                                                  ),
                                                  title: 'Crews',
                                                  subtitle:
                                                      'Race together on one leaderboard',
                                                  onTap: () =>
                                                      context.push('/crews'),
                                                  isLast: true,
                                                ),
                                              ],
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),

                                  // The people — You, the faces ordered by who's
                                  // around, Add. Status pills carry the one thing
                                  // worth knowing under each person.
                                  _PeopleStrip(
                                    me: profile,
                                    members: crewOrdered,
                                    racingIds: racingIds,
                                    hotIds: hotIds,
                                    onYou: () => context.push('/my-nuvo'),
                                    onPerson: _openPerson,
                                    onAdd: () => context.push('/crew/add'),
                                  ),

                                  // Empty crew — the two things that fill it: find
                                  // people, share your code.
                                  if (crew.isEmpty) ...[
                                    const SizedBox(height: 18),
                                    _PeopleSurface(
                                      children: [
                                        _ActionRow(
                                          icon: Icons.person_search_rounded,
                                          title: 'Find people',
                                          subtitle:
                                              'Name, @username or member code',
                                          onTap: () =>
                                              context.push('/crew/add'),
                                        ),
                                        _ActionRow(
                                          icon: Icons.qr_code_rounded,
                                          title: 'Your member code',
                                          subtitle: profile.memberId,
                                          actionLabel: 'My Nuvo',
                                          onTap: () => context.push('/my-nuvo'),
                                          isLast: true,
                                        ),
                                      ],
                                    ),
                                  ],

                                  // Requests — people knocking, at utility weight.
                                  // Incoming first: an ask aimed at me outranks one I
                                  // sent.
                                  if (requests.isNotEmpty ||
                                      outgoing.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    _RequestSurface(
                                      incoming: requests,
                                      outgoing: outgoing,
                                      pending: pending,
                                      onAccept: _acceptRequest,
                                      onDecline: _declineRequest,
                                      onCancel: _cancelRequest,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const FoldGap(20),
                            // Races running with the crew, one section each,
                            // so the first screen can fit whole cards.
                            ..._CrewRacesNow(
                              liveItems: liveItems,
                              ongoing: activeRaces,
                              myId: myId,
                              crewIds: crewIds,
                              reactingIds: activityState.reactingItemIds,
                              onOpen: (r) => context.push('/race/${r.id}'),
                              onOpenLive: _openCrewActivity,
                              onReact: _react,
                            ).items(),
                          ]
                          // ── Activity — what the crew has done.
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NuvoSpacing.pageHorizontal,
                              ),
                              child: _FeedColumn(
                                items: feedItems,
                                reactingIds: activityState.reactingItemIds,
                                crew: crew,
                                myId: myId,
                                racesById: racesById,
                                busyIds: _ctaBusy,
                                emptyNote:
                                    'Race, finish, set a personal best — your friends\' moves land here.',
                                onTap: _openCrewActivity,
                                onPerson: (i) => _tapFeedPerson(i, crew),
                                onReact: _react,
                                actionFor: (i) =>
                                    _actionFor(i, myId, racesById),
                              ),
                            ),
                        ],
                      ],
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: NuvoBottomNav.bottomPadding(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Soft fade so rows scrolling toward the dock ease out instead
            // of being sliced by it.
            Positioned(
              left: 0,
              right: 0,
              // Ends at the dock's top edge (the body runs under the dock).
              bottom: MediaQuery.paddingOf(context).bottom,
              height: 28,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('nuvo-bottom-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        context.themeColors.page.withValues(alpha: 0),
                        context.themeColors.page,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
//
// Standings order + progress text come from race_display.dart
// (serverRankedParticipants / raceProgressLabel) — scoring direction and
// "/target" semantics live in the race system, so Crew never re-sorts by raw
// score or guesses the format.

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: AppTextStyles.sectionTitle);
  }
}

// ── Social feed ────────────────────────────────────────────────────────────
//
// The person is the card, not the race. Each post is a standalone card:
// who's it about up top, what they did as the headline, a context block
// only when the event carries one (score, result, PB), then reactions and
// the one social action the post earns. A `race_live` item renders the
// canonical LIVE card — it's a feed post like any other, pinned to the top
// because it's happening now.

/// A resolved post CTA — the label and the action, computed by the screen
/// (it owns routing + mutations) and handed to the card.
class _PostAction {
  const _PostAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
}

class _FeedColumn extends StatelessWidget {
  const _FeedColumn({
    required this.items,
    required this.reactingIds,
    required this.crew,
    required this.myId,
    required this.racesById,
    required this.busyIds,
    required this.emptyNote,
    required this.onTap,
    required this.onPerson,
    required this.onReact,
    required this.actionFor,
  });

  final List<CrewActivityItem> items;
  final Set<String> reactingIds;
  final List<PublicUser> crew;
  final String myId;
  final Map<String, Race> racesById;
  final Set<String> busyIds;
  final String emptyNote;
  final ValueChanged<CrewActivityItem> onTap;
  final ValueChanged<CrewActivityItem> onPerson;
  final void Function(CrewActivityItem item, String emoji) onReact;
  final _PostAction? Function(CrewActivityItem item) actionFor;

  @override
  Widget build(BuildContext context) {
    // Live posts pin to the top — they're the only thing happening right
    // now; everything else stays chronological.
    final ordered = [...items]
      ..sort((a, b) {
        final aLive = a.live != null ? 1 : 0;
        final bLive = b.live != null ? 1 : 0;
        if (aLive != bLive) return bLive - aLive;
        return b.occurredAt.compareTo(a.occurredAt);
      });
    if (ordered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: _EmptyNote(text: emptyNote),
      );
    }
    final levels = [
      for (final it in ordered) _feedLevelOf(it, myId, racesById),
    ];
    return Column(
      children: [
        for (var i = 0, liveSeen = 0; i < ordered.length; i++)
          NuvoStaggerIn(
            index: i,
            child: Column(
              children: [
                _feedTile(
                  ordered[i],
                  level: levels[i],
                  race: racesById[ordered[i].raceId],
                  myId: myId,
                  busy: reactingIds.contains(ordered[i].id),
                  action: actionFor(ordered[i]),
                  actionBusy: busyIds.contains(ordered[i].id),
                  onTap: onTap,
                  onPerson: onPerson,
                  onReact: onReact,
                  // The first live race is the room's pulse; a second one
                  // compacts so live cards never stack into a wall.
                  liveVariant: ordered[i].live != null && liveSeen++ > 0
                      ? NuvoLiveRaceCardVariant.compact
                      : NuvoLiveRaceCardVariant.primary,
                ),
                if (i < ordered.length - 1)
                  _feedSpacer(
                    context,
                    _feedWeightOf(ordered[i], levels[i]),
                    _feedWeightOf(ordered[i + 1], levels[i + 1]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Lifecycle/reaction notes — real activity, but micro weight: a timeline
/// row, not a card competing with races.
const _microFeedTypes = {
  'reaction',
  'crew_connected',
  'crew_request',
  'crew_request_accepted',
  'crew_request_declined',
  'race_joined',
  'attempt_started',
  'progress_accepted',
  // Proof in flight is informational — a timeline note, never weighted
  // like a rivalry moment.
  'proof_submitted',
};

/// 1 = social moment · 2 = activity · 3 = utility/micro. Level 1 is earned
/// by live races, events landing on me (passed me, my result, my race
/// starting), and direct asks (an invite is inherently to me; a rematch
/// call is).
int _feedLevelOf(
  CrewActivityItem item,
  String myId,
  Map<String, Race> racesById,
) {
  if (_microFeedTypes.contains(item.type)) return 3;
  if (item.live != null) return 1;
  switch (item.type) {
    case 'rank_changed':
    case 'lead_changed':
      return item.involvesUser(myId) ? 1 : 2;
    case 'race_invite':
      return 1;
    case 'rematch_requested':
    case 'race_started':
    case 'race_finished':
    case 'winner_determined':
    case 'participant_finished':
      return item.involvesUser(myId) ||
              (racesById[item.raceId]?.isParticipant(myId) ?? false)
          ? 1
          : 2;
    default:
      return 2;
  }
}

/// Visual weight — how much room an item takes on the page. Distinct from
/// [_feedLevelOf] (relevance): a live card is always its own object, a
/// micro row is timeline activity, everything else is a social post.
enum _FeedWeight { post, live, micro }

_FeedWeight _feedWeightOf(CrewActivityItem item, int level) {
  if (item.live != null) return _FeedWeight.live;
  return level == 3 ? _FeedWeight.micro : _FeedWeight.post;
}

/// The gap that follows an item — whitespace does the separating now that
/// featured moments carry their own tonal territory. Micro rows butt
/// together so a run of them reads as one cluster; everything gets real
/// breathing before the next substantial object.
double _feedGapAfter(_FeedWeight cur, _FeedWeight next) {
  if (cur == _FeedWeight.micro && next == _FeedWeight.micro) return 0;
  return switch ((cur, next)) {
    (_FeedWeight.micro, _) => 8.0,
    (_, _FeedWeight.micro) => 6.0,
    _ => 8.0,
  };
}

/// The separator between feed items — whitespace carries micro
/// transitions, but two substantial posts in a row get a hairline: the
/// rhythm mark that keeps a stream of events from dissolving into one
/// undifferentiated text column.
Widget _feedSpacer(BuildContext context, _FeedWeight cur, _FeedWeight next) {
  if (cur == _FeedWeight.post && next == _FeedWeight.post) {
    return Column(
      children: [
        const SizedBox(height: 4),
        Container(height: 1, color: context.themeColors.divider),
        const SizedBox(height: 5),
      ],
    );
  }
  return SizedBox(height: _feedGapAfter(cur, next));
}

/// Shared by the chronological feed and the For-you relevance surface.
Widget _feedTile(
  CrewActivityItem item, {
  required int level,
  required Race? race,
  required String myId,
  required bool busy,
  required _PostAction? action,
  required bool actionBusy,
  required ValueChanged<CrewActivityItem> onTap,
  required ValueChanged<CrewActivityItem> onPerson,
  required void Function(CrewActivityItem item, String emoji) onReact,
  NuvoLiveRaceCardVariant liveVariant = NuvoLiveRaceCardVariant.primary,
}) {
  if (level == 3) {
    return _MicroActivityRow(
      item: item,
      onTap: () => onTap(item),
      onPerson: () => onPerson(item),
    );
  }
  if (item.live != null) {
    return _LiveRaceCard(
      item: item,
      busy: busy,
      variant: liveVariant,
      onTap: () => onTap(item),
      onReact: (emoji) => onReact(item, emoji),
    );
  }
  return _SocialPostCard(
    item: item,
    race: race,
    myId: myId,
    prominent: level == 1,
    busy: busy,
    action: action,
    actionBusy: actionBusy,
    onTap: () => onTap(item),
    onPerson: () => onPerson(item),
    onReact: (emoji) => onReact(item, emoji),
  );
}

/// The For-you centerpiece — one moment of consequence, not another row.
///
/// Fed only by [_heroRaceFor]: an active shared race I'm inside — YOU vs
/// the person ahead (or behind, when I lead), real scores, the gap in
/// plain words. Finished races and races I'm not in never reach this
/// card; they render at row weight in the lists around it.
///
/// The whole card opens the race — the same destination as every other
/// race surface.
class _CrewHeroCard extends StatelessWidget {
  const _CrewHeroCard({
    required this.race,
    required this.myId,
    required this.onTap,
  });

  final Race race;
  final String myId;
  final VoidCallback onTap;

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'N';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String _firstName(String name) {
    final first = name.trim().split(RegExp(r'\s+')).firstOrNull ?? '';
    return first.isEmpty ? 'Someone' : first;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final ranked = serverRankedParticipants(race);
    if (ranked.isEmpty) return const SizedBox.shrink();

    final me = race.participantFor(myId);
    final finished = raceIsCompleted(race);
    final leader = ranked.first;

    // The rival stands left, me on the right — my read of the score is
    // always "their number, then mine". Who I'm measured against: the
    // leader while I chase, the runner-up while I lead; when I'm not in
    // the race, it's the top pair.
    final left = me == null
        ? leader
        : (leader.userId == myId
              ? (ranked.length > 1 ? ranked[1] : null)
              : leader);
    final right = me ?? (ranked.length > 1 ? ranked[1] : null);

    // The consequence line — plain words, colored by what it means for me.
    final status = _statusLine(
      muted: c.inkSubtle,
      finished: finished,
      me: me,
      left: left,
      right: right,
      leader: leader,
      rank: rankForUser(race, myId),
    );

    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          border: Border.all(color: c.border, width: 2),
          boxShadow: AppShadows.hardOffset(
            c.inkShadow,
            offset: const Offset(7, 7),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    race.displayTitle,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: c.inkDim,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (finished)
                  Text(
                    'FINISHED',
                    style: AppTextStyles.labelUppercase(10, color: c.inkSubtle),
                  )
                else ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: NuvoColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'LIVE',
                    style: AppTextStyles.labelUppercase(
                      10,
                      color: context.dangerInk,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // The duel — each racer is a name-over-score column with their
            // face attached. The rival stands left, me on the right in
            // blue; a centered VS holds the tension between them.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (left != null)
                  Expanded(
                    child: _HeroDuel(
                      participant: left,
                      isMe: left.userId == myId,
                      alignEnd: false,
                    ),
                  )
                else
                  const Expanded(child: SizedBox.shrink()),
                if (left != null && right != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      'VS',
                      style: AppTextStyles.labelUppercase(10, color: c.inkDim),
                    ),
                  ),
                if (right != null)
                  Expanded(
                    child: _HeroDuel(
                      participant: right,
                      isMe: right.userId == myId,
                      alignEnd: true,
                    ),
                  )
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: 10),
            // The consequence in plain words — "Noah leads by 2" — colored
            // by what it means for me, centered under the duel.
            Text(
              status.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: status.color,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Divider(height: 1, thickness: 1, color: c.divider),
            const SizedBox(height: 9),
            Row(
              children: [
                const Spacer(),
                Text(
                  finished ? 'See result' : 'See race',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.blueInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: context.blueInk,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ({String text, Color color}) _statusLine({
    required Color muted,
    required bool finished,
    required RaceParticipant? me,
    required RaceParticipant? left,
    required RaceParticipant? right,
    required RaceParticipant leader,
    required int? rank,
  }) {
    if (finished) {
      if (me == null || rank == null) {
        return (
          text: '${_firstName(leader.displayName)} took it',
          color: NuvoColors.gold,
        );
      }
      if (rank == 1) {
        return (text: 'You took it', color: NuvoColors.gold);
      }
      return (
        text: '${_firstName(leader.displayName)} took it · you placed #$rank',
        color: muted,
      );
    }

    if (me == null) {
      return (
        text: right == null
            ? '${_firstName(leader.displayName)} is racing'
            : '${_firstName(leader.displayName)} in front',
        color: muted,
      );
    }

    final ctx = race.viewerContext;
    final leading = ctx?.isLeading ?? leader.userId == myId;
    // The rival sits left — tied/gap are measured against them, never
    // against my own score.
    final tied =
        ctx?.isTied ?? (left != null && left.progressValue == me.progressValue);
    final gap =
        ctx?.gapToLeader?.abs() ??
        (left != null ? (left.progressValue - me.progressValue).abs() : 0);

    if (tied) {
      return (text: 'Dead even', color: NuvoColors.blue);
    }
    if (leading) {
      return (
        text: 'You lead by ${raceScoreLabel(race, gap)}',
        color: NuvoColors.gold,
      );
    }
    if (left == null || gap <= 0) {
      return (text: 'On the start line', color: muted);
    }
    return (
      text:
          '${_firstName(leader.displayName)} leads by ${raceScoreLabel(race, gap)}',
      color: NuvoColors.blue,
    );
  }
}

/// One side of the hero matchup — the racer's face beside their name,
/// then their score large underneath. "You" replaces my name and my
/// score reads blue; the rival stays navy.
class _HeroDuel extends StatelessWidget {
  const _HeroDuel({
    required this.participant,
    required this.isMe,
    required this.alignEnd,
  });

  final RaceParticipant participant;
  final bool isMe;

  /// Right column mirrors: name then face, score right-aligned.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final avatar = NuvoAvatar(
      initials: _CrewHeroCard._initialsFor(participant.displayName),
      size: 26,
      photoUrl: participant.profilePhotoUrl,
      borderColor: c.divider,
      borderWidth: 1.25,
    );
    final name = Flexible(
      child: Text(
        isMe ? 'You' : _CrewHeroCard._firstName(participant.displayName),
        style: AppTextStyles.labelSmall.copyWith(
          color: isMe ? context.blueInk : c.inkMuted,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: alignEnd
              ? [name, const SizedBox(width: 6), avatar]
              : [avatar, const SizedBox(width: 6), name],
        ),
        const SizedBox(height: 3),
        Text(
          '${participant.progressValue}',
          style: AppTextStyles.number(
            30,
            color: isMe ? context.blueInk : c.ink,
            weight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

/// Level 3 — a micro activity row: one line of who-did-what + timestamp.
/// No card chrome, no reaction bar; these are stream texture, not moments.
class _MicroActivityRow extends StatelessWidget {
  const _MicroActivityRow({
    required this.item,
    required this.onTap,
    required this.onPerson,
  });

  final CrewActivityItem item;
  final VoidCallback onTap;
  final VoidCallback onPerson;

  @override
  Widget build(BuildContext context) {
    // Reactions on a micro event are context, not a bar — show the totals
    // as a tiny suffix rather than three chips.
    final reactionBits = [
      for (final code in kReactionEmojis)
        if ((item.reactions[code] ?? 0) > 0)
          '${kReactionGlyphs[code]}${item.reactions[code]}',
    ].join(' ');
    return NuvoPressable(
      onTap: item.destination == null ? null : onTap,
      haptic: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            NuvoPressable(
              onTap: item.actor == null ? null : onPerson,
              scale: 0.94,
              haptic: false,
              child: NuvoAvatar(
                initials: notificationInitials(item.actor?.displayName),
                photoUrl: item.actor?.profilePhotoUrl,
                size: 22,
                bgColor: nuvoAvatarColorFor(item.id),
                textColor: NuvoColors.white,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: item.headline),
                    if (reactionBits.isNotEmpty)
                      TextSpan(
                        text: '  $reactionBits',
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: context.themeColors.inkMuted,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              notificationRelativeTime(item.occurredAt),
              style: AppTextStyles.labelSmall.copyWith(
                color: context.themeColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The person-centric feed post. Every social moment lives directly on
/// the page — hierarchy comes from the content itself (the score matchup,
/// the earned line, the blue action), never from a card wrapped around it.
/// The hard navy-edge + offset-shadow surface stays scarce: hero, live,
/// modal — a feed event is never a physical Nuvo card.
///
/// Composition: avatar + name + timestamp → natural-language headline →
/// the artifact the event carries (a duel, an earned line, a slim race
/// embed) → bare reactions and the one action the post earns.
/// [prominent] — moments that land on me — upgrades the action to its
/// blue pill (`Take it back`, `Rematch`) and nothing else.
/// Minimum tap height of a post's reaction chips and action — the visuals
/// are smaller, the hit area is not.
const double _kPostHitHeight = 40;

class _SocialPostCard extends StatelessWidget {
  const _SocialPostCard({
    required this.item,
    required this.race,
    required this.myId,
    required this.prominent,
    required this.busy,
    required this.action,
    required this.actionBusy,
    required this.onTap,
    required this.onPerson,
    required this.onReact,
  });

  final CrewActivityItem item;
  final Race? race;
  final String myId;

  /// The moment lands on me — a pass, my result, a direct ask. It keeps
  /// the same bare-page grammar as every post; prominence upgrades only
  /// the action to its blue pill.
  final bool prominent;
  final bool busy;
  final _PostAction? action;
  final bool actionBusy;
  final VoidCallback onTap;
  final VoidCallback onPerson;
  final ValueChanged<String> onReact;

  /// The card header already names the actor, so the body drops the
  /// repeated name: "just passed you in X", "accepted your crew request".
  String _stripActor(String text) {
    final name = item.actor?.displayName.trim();
    if (name == null || name.isEmpty) return text;
    for (final prefix in [name, name.split(' ').first]) {
      if (prefix.isNotEmpty && text.startsWith('$prefix ')) {
        return text.substring(prefix.length + 1);
      }
    }
    return text;
  }

  /// Person-first headline — when the event lands on me the card says so:
  /// "just passed you", "took your spot". Everything else keeps the model's
  /// composed headline, minus the name the header already carries.
  String _headline() {
    final overtaken = item.payload['overtakenUserIds'];
    if (item.type == 'rank_changed' &&
        overtaken is List &&
        overtaken.contains(myId)) {
      return 'just passed you in ${item.raceTitle ?? 'a race'}';
    }
    if (item.type == 'lead_changed' &&
        item.payload['displacedUserId'] == myId) {
      return 'just took your spot';
    }
    return _stripActor(item.headline);
  }

  /// The middle of the post — the fact the event carries, rendered as
  /// data, not a panel: a score matchup becomes two columns and a split
  /// bar, a win becomes a gold earned line, a new race gets the slim ice
  /// embed. Everything else is a line of type.
  Widget? _artifact() {
    switch (item.type) {
      case 'rank_changed':
        final overtaken = item.payload['overtakenUserIds'];
        final passedMe = overtaken is List && overtaken.contains(myId);
        if (!passedMe) return null;
        // The score IS the object — "Noah 41 · You 39" as a duel, not a
        // sentence in a rounded rectangle.
        if (race != null) {
          final standings = serverRankedParticipants(race!);
          final actor = standings
              .where((p) => p.userId == item.actor?.id)
              .firstOrNull;
          final me = standings.where((p) => p.userId == myId).firstOrNull;
          if (actor != null && me != null) {
            return _PostMatchup(
              leftName: actor.displayName.split(' ').first,
              leftScore: actor.progressValue,
              rightName: 'You',
              rightScore: me.progressValue,
              rightIsMe: true,
            );
          }
        }
        final rank = (item.payload['newRank'] as num?)?.toInt();
        if (rank != null) {
          return _EarnedFact(lines: ['Now #$rank ahead of you']);
        }
        return null;
      case 'participant_finished':
        final score = (item.payload['score'] as num?)?.toInt();
        int? rank;
        if (race != null) {
          rank = race!.participants
              .where((p) => p.userId == item.actor?.id)
              .firstOrNull
              ?.rank;
        }
        if (score == null) return null;
        final metric = race?.metric != null
            ? ' ${race!.metric!.toUpperCase()}'
            : '';
        return _EarnedFact(
          lines: [
            if (rank == 1) '🏆 1ST' else '$score$metric',
            if (rank == 1) '$score$metric' else if (rank != null) '#$rank',
          ],
          // A first place earns gold on the earned line — nowhere else.
          accent: rank == 1 ? NuvoColors.gold : null,
        );
      case 'personal_best':
        final best = (item.payload['newBest'] as num?)?.toInt();
        final prev = (item.payload['previousBest'] as num?)?.toInt();
        if (best == null) return null;
        final delta = prev != null ? best - prev : null;
        final metric = (item.payload['metric'] as String?)?.toUpperCase();
        return _EarnedFact(
          lines: [
            '$best${metric != null ? ' $metric' : ''}${delta != null && delta > 0 ? '  ↗ +$delta' : ''}',
          ],
          // PB is performance family — teal, not gold (wins own gold).
          accent: NuvoColors.avatarTeal,
        );
      case 'race_finished':
      case 'winner_determined':
        final score =
            (item.payload['score'] as num?)?.toInt() ??
            (item.payload['topScore'] as num?)?.toInt();
        final mine = item.payload['winnerUserId'] == myId;
        return _EarnedFact(
          lines: [if (mine) '🏆 YOU WON', if (score != null) 'Top score $score']
            ..removeWhere((s) => s.isEmpty),
          accent: mine ? NuvoColors.gold : null,
        );
      case 'race_created':
        final count = race?.participants.length;
        return _PostContext(
          lines: [
            if (item.raceTitle != null) item.raceTitle!.toUpperCase(),
            if (count != null) '$count joined',
          ]..removeWhere((s) => s.isEmpty),
        );
      default:
        return null;
    }
  }

  /// The soft territory a featured moment earns — the social color system:
  /// ice-blue for a rivalry in motion, teal for a personal best, violet
  /// for an invite, pale green for a teammate's verified finish, warm
  /// cream only when a WIN lands. Standard posts stay on the bare page.
  Color _bandColor(BuildContext context) {
    final sem = context.semanticColors;
    switch (item.type) {
      case 'personal_best':
        return NuvoColors.avatarTeal.withValues(alpha: 0.10);
      case 'race_invite':
      case 'rematch_requested':
        return NuvoColors.avatarPlum.withValues(alpha: 0.10);
      case 'race_finished':
      case 'winner_determined':
        return item.payload['winnerUserId'] == myId
            ? sem.warning.surface
            : NuvoColors.success.withValues(alpha: 0.07);
      case 'participant_finished':
        final rank = race?.participants
            .where((p) => p.userId == item.actor?.id)
            .firstOrNull
            ?.rank;
        return rank == 1
            ? sem.warning.surface
            : NuvoColors.success.withValues(alpha: 0.07);
      default:
        return sem.neutral.surface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final artifact = _artifact();
    // Every post sits directly on the page — the content carries the
    // hierarchy (score matchup, earned line, blue action), never a card.
    // [prominent] earns two things: a soft tonal band the whole post lives
    // inside (a territory, not a container — no border, no shadow) and the
    // action's blue pill.
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NuvoPressable(
          onTap: onPerson,
          scale: 0.94,
          haptic: false,
          child: NuvoAvatar(
            initials: notificationInitials(item.actor?.displayName),
            photoUrl: item.actor?.profilePhotoUrl,
            size: 32,
            bgColor: nuvoAvatarColorFor(item.id),
            textColor: NuvoColors.white,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: NuvoPressable(
                      onTap: onPerson,
                      haptic: false,
                      child: Text(
                        item.actor?.displayName ?? 'Nuvo member',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    notificationRelativeTime(item.occurredAt),
                    style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
                  ),
                  if (!item.read)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: NuvoColors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              Text(
                _headline(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              if (artifact != null) ...[const SizedBox(height: 3), artifact],
              if (item.isReactionable || action != null)
                Row(
                  children: [
                    if (item.isReactionable)
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _ReactionBar(
                            item: item,
                            busy: busy,
                            onReact: onReact,
                            hitHeight: _kPostHitHeight,
                          ),
                        ),
                      ),
                    // The action gets the other half of the row, right-aligned,
                    // and scales down only when the row is genuinely too
                    // narrow (320px at large text) — it never overflows.
                    if (action != null)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: _PostActionButton(
                              action: action!,
                              busy: actionBusy,
                              strong: prominent,
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                  ],
                ),
            ],
          ),
        ),
      ],
    );

    // The post itself owns no separators — the feed decides the gap based
    // on what comes next ([_feedRhythmAfter]). A featured moment wraps
    // the same body in its tonal band; minimal radius, flush with the
    // feed column — the page changes tone, nothing floats.
    return NuvoPressable(
      onTap: item.destination == null ? null : onTap,
      haptic: false,
      child: prominent
          ? Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              decoration: BoxDecoration(
                color: _bandColor(context),
                borderRadius: BorderRadius.circular(NuvoRadii.sm),
              ),
              child: body,
            )
          : Padding(padding: const EdgeInsets.only(top: 6), child: body),
    );
  }
}

/// The score as the object — an overtake rendered as a duel: names over
/// numerals, mine on the right in blue, a proportional split bar under
/// them showing who owns the lead. No panel, no border — the numbers
/// themselves are the interesting part.
class _PostMatchup extends StatelessWidget {
  const _PostMatchup({
    required this.leftName,
    required this.leftScore,
    required this.rightName,
    required this.rightScore,
    this.rightIsMe = false,
  });

  final String leftName;
  final int leftScore;
  final String rightName;
  final int rightScore;
  final bool rightIsMe;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final l = leftScore <= 0 ? 1 : leftScore;
    final r = rightScore <= 0 ? 1 : rightScore;
    TextStyle label(Color color) => AppTextStyles.labelSmall.copyWith(
      color: color,
      fontWeight: FontWeight.w800,
    );
    // One row: "Noah 41 [split bar] 39 You" — the score is the object. The
    // NAME is what gives way (ellipsis) when space runs out; scores never do.
    Widget side({
      required String name,
      required int score,
      required Color scoreColor,
      required bool scoreFirst,
    }) {
      final nameText = Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: label(c.inkMuted),
        ),
      );
      final scoreText = Text(
        '$score',
        maxLines: 1,
        style: AppTextStyles.number(
          16,
          color: scoreColor,
          weight: FontWeight.w900,
        ),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: scoreFirst
            ? [scoreText, const SizedBox(width: 4), nameText]
            : [nameText, const SizedBox(width: 4), scoreText],
      );
    }

    return Row(
      children: [
        Flexible(
          flex: 3,
          child: side(
            name: leftName,
            score: leftScore,
            scoreColor: c.ink,
            scoreFirst: false,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              child: Row(
                children: [
                  Expanded(
                    flex: l,
                    child: ColoredBox(color: c.track),
                  ),
                  Expanded(
                    flex: r,
                    child: ColoredBox(
                      color: rightIsMe
                          ? NuvoColors.blue
                          : c.track.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 3,
          child: side(
            name: rightName,
            score: rightScore,
            scoreColor: rightIsMe ? context.blueInk : c.ink,
            scoreFirst: true,
          ),
        ),
      ],
    );
  }
}

/// An earned fact as type, not a panel — a first place, a personal best,
/// a top score. [accent] colors only the earned line (gold for a win);
/// supporting lines stay muted. Indented to the post's text column.
class _EarnedFact extends StatelessWidget {
  const _EarnedFact({required this.lines, this.accent});

  final List<String> lines;

  /// Accent for the first line — gold (`NuvoColors.gold`) for wins and
  /// bests; null keeps the default ink.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.zero,
              child: Text(
                lines[i],
                maxLines: 2,
                style:
                    (i == 0
                            ? AppTextStyles.titleMedium
                            : AppTextStyles.bodySmall.copyWith(
                                color: context.themeColors.inkMuted,
                              ))
                        .copyWith(
                          color: i == 0 ? (accent ?? c.ink) : c.inkMuted,
                          fontWeight: FontWeight.w800,
                        ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The one action a post earns — a compact blue pill on featured moments
/// (Take it back, Rematch), a quiet blue text action on standard posts.
/// Never half the post's width, never a second visual headline.
class _PostActionButton extends StatelessWidget {
  const _PostActionButton({
    required this.action,
    required this.busy,
    required this.strong,
  });

  final _PostAction action;
  final bool busy;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      busy ? '…' : action.label,
      style: AppTextStyles.labelMedium.copyWith(
        color: strong ? NuvoColors.white : context.blueInk,
        fontWeight: FontWeight.w800,
      ),
    );
    // The visual stays small; the tap area is a full [_kPostHitHeight] row.
    if (!strong) {
      return NuvoPressable(
        onTap: busy ? null : action.onTap,
        haptic: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _kPostHitHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(widthFactor: 1, child: label),
          ),
        ),
      );
    }
    return PressableScale(
      onTap: busy ? null : action.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kPostHitHeight),
        child: Center(
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(999),
            ),
            child: label,
          ),
        ),
      ),
    );
  }
}

/// The one remaining embedded object — a race someone just started gets a
/// slim ice panel ("come join this"), never outlined. Scores and results
/// render as type via [_EarnedFact] / [_PostMatchup], not panels.
class _PostContext extends StatelessWidget {
  const _PostContext({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.sm),
        border: Border.all(color: c.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                lines[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: i == 0 ? c.ink : c.inkMuted,
                  fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The feed lens switch — demoted to a quiet text row under a hairline.
/// It filters the stream; it doesn't claim the page. Counts are
/// contextual: only shown when there's actually something inside.
class _CrewTabs extends StatelessWidget {
  const _CrewTabs({
    required this.selected,
    required this.onSelect,
    this.counts = const [],
  });

  final int selected;
  final ValueChanged<int> onSelect;

  /// Optional per-tab content counts — wired to the live derivations, so
  /// "People 2" means there are two requests waiting.
  final List<int?> counts;

  static const _labels = ['People', 'Activity'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 18),
            Expanded(
              child: NuvoPressable(
                onTap: () => onSelect(i),
                scale: 0.96,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.only(top: 6, bottom: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected == i
                            ? context.themeColors.border
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  // Fixed-width slots — the labels are lens chrome, so
                  // their scale is pinned: at 1.4 a third of 320px cannot
                  // take "Activity 12" scaled up without truncating.
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.15,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: selected == i
                                  ? context.themeColors.ink
                                  : context.themeColors.inkMuted,
                              fontWeight: FontWeight.w800,
                            ),
                            child: Text(
                              _labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (i < counts.length && (counts[i] ?? 0) > 0) ...[
                          const SizedBox(width: 5),
                          Text(
                            '${counts[i]}',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: selected == i
                                  ? context.blueInk
                                  : context.themeColors.inkDim,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The races running with my crew right now, shown under People: LIVE →
/// racing now. Live races render the same canonical `_LiveRaceCard` the feed
/// uses (same `race_live` payload, same truth) and are deduped out of the
/// active group; each section collapses entirely when it has nothing to say.
class _CrewRacesNow extends StatelessWidget {
  const _CrewRacesNow({
    required this.liveItems,
    required this.ongoing,
    required this.myId,
    required this.crewIds,
    required this.reactingIds,
    required this.onOpen,
    required this.onOpenLive,
    required this.onReact,
  });

  /// Feed items carrying a `race_live` spectator payload — the live state
  /// is projected first.
  final List<CrewActivityItem> liveItems;
  final List<Race> ongoing;
  final String myId;
  final Set<String> crewIds;
  final Set<String> reactingIds;
  final ValueChanged<Race> onOpen;
  final ValueChanged<CrewActivityItem> onOpenLive;
  final void Function(CrewActivityItem item, String emoji) onReact;

  /// The same content as [build], one section per card with flexible gaps
  /// between them, for [FoldFitColumn].
  List<Widget> items() {
    const pad = EdgeInsets.symmetric(horizontal: NuvoSpacing.pageHorizontal);
    Widget section(Widget child) => Padding(padding: pad, child: child);
    if (liveItems.isEmpty && ongoing.isEmpty) return [section(_emptyNote())];
    return [
      if (liveItems.isNotEmpty) ...[
        section(const _LiveSectionLabel()),
        const FoldGap(8),
        for (final (i, item) in liveItems.take(2).indexed)
          section(
            _LiveRaceCard(
              item: item,
              busy: reactingIds.contains(item.id),
              onTap: () => onOpenLive(item),
              onReact: (emoji) => onReact(item, emoji),
              variant: i == 0
                  ? NuvoLiveRaceCardVariant.primary
                  : NuvoLiveRaceCardVariant.compact,
            ),
          ),
      ],
      if (ongoing.isNotEmpty) ...[
        FoldGap(liveItems.isNotEmpty ? 6 : 0),
        section(const _SectionLabel(label: 'Racing with your friends')),
        const FoldGap(8),
        for (final race in ongoing.take(3)) ...[
          section(
            _ActiveRaceCard(
              race: race,
              myId: myId,
              crewIds: crewIds,
              onTap: () => onOpen(race),
            ),
          ),
          const FoldGap(10),
        ],
      ],
    ];
  }

  Widget _emptyNote() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: _EmptyNote(
      text:
          'No races running with your friends right now. Start one from '
          'Compete.',
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (liveItems.isEmpty && ongoing.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: _EmptyNote(
          text:
              'No races running with your friends right now. Start one from '
              'Compete.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── LIVE — the strongest state on this tab: red pulse + label,
        // real scores, Watch. One primary moment; a second live race goes
        // compact so two cards don't stack into another heavyweight block.
        if (liveItems.isNotEmpty) ...[
          const _LiveSectionLabel(),
          const SizedBox(height: 8),
          for (final (i, item) in liveItems.take(2).indexed)
            _LiveRaceCard(
              item: item,
              busy: reactingIds.contains(item.id),
              onTap: () => onOpenLive(item),
              onReact: (emoji) => onReact(item, emoji),
              variant: i == 0
                  ? NuvoLiveRaceCardVariant.primary
                  : NuvoLiveRaceCardVariant.compact,
            ),
        ],

        // ── Happening now — active shared races as compact competitive
        // cards: standings slice, progress, who's in. Not title/date rows.
        if (ongoing.isNotEmpty) ...[
          if (liveItems.isNotEmpty) const SizedBox(height: 6),
          const _SectionLabel(label: 'Racing with your friends'),
          const SizedBox(height: 8),
          for (final race in ongoing.take(3)) ...[
            _ActiveRaceCard(
              race: race,
              myId: myId,
              crewIds: crewIds,
              onTap: () => onOpen(race),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

/// The LIVE group header — a red pulse dot + label, matching the card below.
class _LiveSectionLabel extends StatelessWidget {
  const _LiveSectionLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: NuvoColors.danger,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text('Live now', style: AppTextStyles.sectionTitle),
      ],
    );
  }
}

/// An active shared race as competitive state, not a database row: the
/// standings slice (me always visible), a progress bar for the leader's
/// pace, and who's in. One tap opens the race room.
class _ActiveRaceCard extends StatelessWidget {
  const _ActiveRaceCard({
    required this.race,
    required this.myId,
    required this.crewIds,
    required this.onTap,
  });

  final Race race;
  final String myId;
  final Set<String> crewIds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final standings = serverRankedParticipants(race);
    final top = standings.take(3).toList();
    final me = standings.where((p) => p.userId == myId).firstOrNull;
    if (me != null && top.every((p) => p.userId != myId)) {
      top.add(me);
    }
    final crewCount = standings.where((p) => crewIds.contains(p.userId)).length;
    final myRank = rankForUser(race, myId);
    // Canonical lane geometry — the same marks as Verify's queue: my bead
    // fills the lane, the nearest rival is a navy dot, the goal is a ring.
    final geo = raceLaneGeometry(race, myId);
    final nearest = raceNearestRival(race, myId);
    final nearestMark = nearest == null
        ? null
        : geo.rivals.where((r) => r.racer.userId == nearest.userId).firstOrNull;
    final showLane = geo.hasGoal || geo.viewer != null || nearestMark != null;
    String? daysLeft;
    final finish = DateTime.tryParse(race.finishLineAt ?? '');
    if (finish != null) {
      final d = finish.difference(DateTime.now()).inDays;
      daysLeft = d <= 0 ? 'Ends today' : '${d}d left';
    }
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: context.themeColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.card),
          border: Border.all(color: context.themeColors.divider, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    race.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.themeColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                // Where I stand in this race — live lead reads green.
                if (myRank != null) ...[
                  Text(
                    _ordinal(myRank),
                    style: AppTextStyles.placementLabel(
                      size: 12,
                      color: myRank == 1
                          ? context.successInk
                          : context.themeColors.inkSubtle,
                    ),
                  ),
                  if (daysLeft != null)
                    Text(
                      '  ·  ',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.themeColors.inkMuted,
                      ),
                    ),
                ],
                if (daysLeft != null)
                  Text(
                    daysLeft,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: context.themeColors.inkMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // "Riley 67 · Maya 61 · You 58" — the competitive picture in one
            // line; me gets the blue treatment.
            Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < top.length; i++) ...[
                    if (i > 0)
                      TextSpan(
                        text: '  ·  ',
                        style: TextStyle(color: context.themeColors.inkMuted),
                      ),
                    TextSpan(
                      text: top[i].userId == myId
                          ? 'You'
                          : top[i].displayName.split(' ').first,
                      style: TextStyle(
                        color: context.themeColors.ink,
                        fontWeight: top[i].userId == myId
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: ' ${raceScoreLabel(race, top[i].progressValue)}',
                      style: TextStyle(
                        color: top[i].userId == myId
                            ? context.blueInk
                            : context.themeColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.themeColors.inkMuted,
              ),
            ),
            if (showLane) ...[
              const SizedBox(height: 9),
              // Compact canonical lane — viewer bead + rival dot + goal
              // ring, same marks the rest of the app uses.
              RaceMarkerTrack(
                compact: true,
                fillColor: NuvoColors.blue,
                hasGoal: geo.hasGoal,
                markers: [
                  if (nearestMark != null)
                    RaceTrackMarker(
                      fraction: nearestMark.fraction,
                      label: '',
                      color: context.themeColors.ink,
                    ),
                  if (geo.viewer != null)
                    RaceTrackMarker(
                      fraction: geo.viewer!,
                      label: '',
                      color: NuvoColors.blue,
                      isViewer: true,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    {
                      '$crewCount from your friends',
                      '${race.participants.length} racing',
                    }.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: context.themeColors.inkMuted,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: context.blueInk,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// The reaction strip — 🔥 👏 💪 chips with aggregate counts. Mine is
/// highlighted; tapping toggles it. Tactile: each chip scales on press and
/// pops with a light haptic (fired by the caller).
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.item,
    required this.busy,
    required this.onReact,
    this.hitHeight = 0,
  });

  final CrewActivityItem item;
  final bool busy;
  final ValueChanged<String> onReact;

  /// Minimum tap height per chip (0 = chip's own size).
  final double hitHeight;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final code in kReactionEmojis)
          Padding(
            padding: EdgeInsets.only(right: hitHeight > 0 ? 2 : 9),
            child: _ReactionChip(
              hitHeight: hitHeight,
              glyph: kReactionGlyphs[code]!,
              count: item.reactions[code] ?? 0,
              mine: item.myReaction == code,
              enabled: !busy,
              onTap: () => onReact(code),
            ),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.glyph,
    required this.count,
    required this.mine,
    required this.enabled,
    required this.onTap,
    this.hitHeight = 0,
  });

  final double hitHeight;
  final String glyph;
  final int count;
  final bool mine;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Native social grammar: an unselected reaction is bare text — glyph
    // and count flow with the post. Only MY reaction earns a surface: a
    // quiet ice fill, no border. A pill around every emoji reads as chrome
    // competing with the event.
    final c = context.themeColors;
    return PressableScale(
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: hitHeight),
        child: Center(
          widthFactor: 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutBack,
            padding: EdgeInsets.symmetric(
              horizontal: mine ? 8 : 3,
              vertical: mine ? 4 : 3,
            ),
            decoration: mine
                ? BoxDecoration(
                    // "You" is highlighted in gold, not a pale blue.
                    color: NuvoColors.gold.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The glyph pops when canonical state flips mine on — a full
                // pop on add, a quieter half-pop on remove.
                NuvoPop(
                  trigger: mine,
                  intensity: mine ? 1.0 : 0.5,
                  child: Text(glyph, style: const TextStyle(fontSize: 13)),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  NuvoNumberFlow(
                    value: count,
                    duration: const Duration(milliseconds: 220),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: mine ? context.blueInk : c.inkMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The canonical live-race presentation contract — "LIVE NOW · Riley vs
/// Maya · scores · time left · Watch". Crew renders whatever the race
/// system's `race_live` payload carries; it never computes live truth.
/// Crew's adapter over `NuvoLiveRaceCard`: maps the canonical `race_live`
/// payload into core standings and injects the reaction bar. All live truth
/// stays server-composed — the card renders `live`, never computes it.
class _LiveRaceCard extends StatelessWidget {
  const _LiveRaceCard({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onReact,
    this.variant = NuvoLiveRaceCardVariant.primary,
  });

  final CrewActivityItem item;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<String> onReact;
  final NuvoLiveRaceCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final live = item.live!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NuvoLiveRaceCard(
        variant: variant,
        title: live.title,
        endsAt: live.endsAt,
        standings: [
          for (final p in live.participants)
            NuvoLiveStanding(
              name: p.name,
              score: p.score,
              rank: p.rank,
              isMe: p.isMe,
            ),
        ],
        onWatch: onTap,
        trailing: item.isReactionable
            ? _ReactionBar(item: item, busy: busy, onReact: onReact)
            : null,
      ),
    );
  }
}

class _CrewHeader extends StatelessWidget {
  const _CrewHeader({
    required this.subtitle,
    required this.onMyCode,
    required this.searchOpen,
    required this.onToggleSearch,
  });

  /// Live pulse line ("5 in your crew · 2 active now") — the header states
  /// the crew's size and presence instead of a static tagline.
  final String subtitle;
  final VoidCallback onMyCode;
  final bool searchOpen;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Page identity ──────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              // Scales down on the narrowest phones instead of ellipsizing
              // the tab title.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Friends',
                  maxLines: 1,
                  style: AppTextStyles.screenTitle,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: searchOpen ? 'Close search' : 'Find people',
              child: NuvoRippleSurface(
                onTap: onToggleSearch,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    searchOpen ? Icons.close_rounded : Icons.search_rounded,
                    color: searchOpen
                        ? context.blueInk
                        : context.themeColors.ink,
                    size: 24,
                  ),
                ),
              ),
            ),
            // Member code lives one tap away, same plain-icon weight as the
            // notification bell beside it.
            Semantics(
              button: true,
              label: 'Show my member code',
              child: NuvoRippleSurface(
                onTap: onMyCode,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.qr_code_rounded,
                    color: context.themeColors.ink,
                    size: 24,
                  ),
                ),
              ),
            ),
            const NotificationBell(),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.themeColors.inkMuted,
          ),
        ),
      ],
    );
  }
}

/// The crew itself — a flat horizontal strip, no container card: You first,
/// faces ordered by who's around, a permanent Add tile at the end. Under
/// each person sits the one thing worth knowing: Racing if they're inside
/// an active shared race, Active if they're around now — nothing is ever
/// fabricated. Tapping a face opens the relationship surface, not a
/// profile page.
class _PeopleStrip extends StatelessWidget {
  const _PeopleStrip({
    required this.me,
    required this.members,
    required this.racingIds,
    required this.hotIds,
    required this.onYou,
    required this.onPerson,
    required this.onAdd,
  });

  final UserProfile me;
  final List<PublicUser> members;

  /// Members inside an active shared race — they earn the "Racing" pill,
  /// which outranks presence.
  final Set<String> racingIds;

  /// Members with a real achievement in the last day — they earn 🔥.
  final Set<String> hotIds;
  final VoidCallback onYou;
  final ValueChanged<PublicUser> onPerson;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final meParts = me.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final meInitials = meParts.isEmpty
        ? 'N'
        : meParts.length == 1
        ? meParts.first[0].toUpperCase()
        : '${meParts[0][0]}${meParts[1][0]}'.toUpperCase();
    return SizedBox(
      height: 78,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _StripTile(
            label: 'You',
            onTap: onYou,
            avatar: NuvoAvatar(
              initials: meInitials,
              size: 44,
              bgColor: NuvoColors.blue,
              textColor: NuvoColors.white,
            ),
          ),
          for (final m in members)
            _StripTile(
              label: m.displayName.split(' ').first,
              status: racingIds.contains(m.id)
                  ? _StripStatus.racing
                  : hotIds.contains(m.id)
                  ? _StripStatus.hot
                  : crewPresenceFor(m.lastActiveAt) == CrewPresence.active
                  ? _StripStatus.active
                  : null,
              onTap: () => onPerson(m),
              avatar: NuvoAvatar(
                initials: m.initials,
                photoUrl: m.profilePhotoUrl,
                size: 44,
                bgColor: nuvoAvatarColorFor(m.id),
                textColor: NuvoColors.white,
              ),
            ),
          _StripTile(
            label: 'Add',
            onTap: onAdd,
            avatar: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.themeColors.panel,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.themeColors.border,
                  width: 1.25,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.person_add_alt_1_rounded,
                color: context.themeColors.ink,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StripStatus { racing, hot, active }

class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.label,
    required this.avatar,
    required this.onTap,
    this.status,
  });

  final String label;
  final Widget avatar;
  final VoidCallback onTap;

  /// The status pill under the name — null renders nothing, never a fake
  /// "away" state.
  final _StripStatus? status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: NuvoPressable(
        onTap: onTap,
        scale: 0.94,
        haptic: false,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: SizedBox(
            width: 58,
            // Fixed-height rail — a 50px tile can't absorb scaled type, so
            // name + status pill are pinned (they ellipsize, never grow).
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.0,
              child: Column(
                children: [
                  SizedBox(width: 44, height: 44, child: Center(child: avatar)),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: context.themeColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 2),
                    _StatusPill(status: status!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tiny status line under a strip name — Racing in blue, 🔥 for a
/// fresh best/win in warm gold, Active in green.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final _StripStatus status;

  @override
  Widget build(BuildContext context) {
    final hot = status == _StripStatus.hot;
    final sem = context.semanticColors;
    final (dot, word, ink) = switch (status) {
      _StripStatus.racing => (NuvoColors.blue, 'Racing', context.blueInk),
      _StripStatus.hot => (NuvoColors.warning, '🔥', sem.warning.on),
      _StripStatus.active => (NuvoColors.success, 'Active', sem.success.on),
    };
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hot)
            Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: AppTextStyles.labelSmall.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 3),
            Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A quiet actionable row inside a people surface — icon + title/subtitle +
/// optional trailing label or chevron. Used for the empty-crew actions.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.actionLabel,
    this.isLast = false,
    this.leading,
  });

  /// Optional custom mark shown in place of [icon] (e.g. [NuvoCrewIcon]).
  final Widget? leading;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? actionLabel;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NuvoPressable(
          onTap: onTap,
          haptic: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.themeColors.panel,
                    borderRadius: BorderRadius.circular(NuvoRadii.md),
                  ),
                  alignment: Alignment.center,
                  child:
                      leading ??
                      Icon(icon, color: context.themeColors.ink, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: context.themeColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.themeColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionLabel != null)
                  Text(
                    actionLabel!,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: context.blueInk,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.themeColors.inkMuted,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: context.themeColors.border.withValues(alpha: 0.7),
            indent: 52,
          ),
      ],
    );
  }
}

/// Square scan control paired with the search field — same border weight and
/// radius as the field so the two read as one input group.
class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Scan a member code',
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: context.themeColors.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.md),
            border: Border.all(color: context.themeColors.border, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.qr_code_scanner_rounded,
            color: context.themeColors.ink,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ── User row ──────────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    this.added = false,
    this.loading = false,
    this.actionLabel,
    this.onPressed,
    this.isLast = false,
    this.subtitle,
  });

  final PublicUser user;
  final bool added;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onPressed;
  final bool isLast;

  /// Explicit subline (e.g. "4 mutual crew" on a search result) — overrides
  /// the handle default.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              NuvoAvatar(
                initials: user.initials,
                photoUrl: user.profilePhotoUrl,
                size: NuvoAvatarSizes.md,
                bgColor: nuvoAvatarColorFor(user.id),
                textColor: NuvoColors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: context.themeColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? user.handleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.themeColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null)
                added
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          actionLabel!,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: context.themeColors.inkSubtle,
                          ),
                        ),
                      )
                    : SizedBox(
                        width: 72,
                        child: NuvoGhostButton(
                          label: loading ? '...' : actionLabel!,
                          small: true,
                          onPressed: loading ? null : onPressed,
                        ),
                      ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: context.themeColors.border.withValues(alpha: 0.7),
            indent: NuvoAvatarSizes.md + 12,
          ),
      ],
    );
  }
}

/// Requests compressed to utility weight — one quiet surface: incoming asks
/// get a single-line row with inline Decline/Accept; sent ones a Pending
/// mark and a cancel affordance. They're asks, not feed content — so they
/// stay above the tabs but no longer own the viewport.
class _RequestSurface extends StatelessWidget {
  const _RequestSurface({
    required this.incoming,
    required this.outgoing,
    required this.pending,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
  });

  final List<PublicUser> incoming;
  final List<PublicUser> outgoing;
  final Set<String> pending;
  final ValueChanged<PublicUser> onAccept;
  final ValueChanged<PublicUser> onDecline;
  final ValueChanged<PublicUser> onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NuvoRadii.card - 1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              if (incoming.isNotEmpty) ...[
                _RequestGroupLabel(
                  label: 'Friend requests',
                  count: incoming.length,
                ),
                for (final user in incoming)
                  _IncomingRequestRow(
                    user: user,
                    busy: pending.contains(user.id),
                    onAccept: () => onAccept(user),
                    onDecline: () => onDecline(user),
                  ),
              ],
              if (outgoing.isNotEmpty) ...[
                _RequestGroupLabel(
                  label: 'Sent',
                  count: outgoing.length,
                  topDivider: incoming.isNotEmpty,
                ),
                for (final user in outgoing)
                  _SentRequestRow(
                    user: user,
                    busy: pending.contains(user.id),
                    onCancel: () => onCancel(user),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestGroupLabel extends StatelessWidget {
  const _RequestGroupLabel({
    required this.label,
    required this.count,
    this.topDivider = false,
  });

  final String label;
  final int count;
  final bool topDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: topDivider
          ? BoxDecoration(
              border: Border(
                top: BorderSide(color: context.themeColors.divider, width: 1),
              ),
            )
          : null,
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: context.themeColors.inkMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.blueInk,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// One incoming ask — single line: face, name, quiet Decline, blue Accept.
class _IncomingRequestRow extends StatelessWidget {
  const _IncomingRequestRow({
    required this.user,
    required this.onAccept,
    required this.onDecline,
    this.busy = false,
  });

  final PublicUser user;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          NuvoAvatar(
            initials: user.initials,
            photoUrl: user.profilePhotoUrl,
            size: 32,
            bgColor: nuvoAvatarColorFor(user.id),
            textColor: NuvoColors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.themeColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _MiniAction(label: 'Decline', onTap: busy ? null : onDecline),
          const SizedBox(width: 4),
          _MiniAction(
            label: 'Accept',
            filled: true,
            onTap: busy ? null : onAccept,
          ),
        ],
      ),
    );
  }
}

/// A request I sent that's still waiting — Pending mark + cancel. Same
/// remove mutation as before; it just no longer takes a card to show it.
class _SentRequestRow extends StatelessWidget {
  const _SentRequestRow({
    required this.user,
    required this.onCancel,
    this.busy = false,
  });

  final PublicUser user;
  final VoidCallback onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          NuvoAvatar(
            initials: user.initials,
            photoUrl: user.profilePhotoUrl,
            size: 32,
            bgColor: nuvoAvatarColorFor(user.id),
            textColor: NuvoColors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.themeColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'Pending',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.themeColors.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          PressableScale(
            onTap: busy ? null : onCancel,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                Icons.close_rounded,
                color: context.themeColors.inkMuted,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small pill used inside compact rows — one filled action (Accept) and
/// quiet text actions beside it. ~30px tall, still an easy tap.
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: filled ? 12 : 8, vertical: 6),
        decoration: filled
            ? BoxDecoration(
                color: NuvoColors.blue,
                borderRadius: BorderRadius.circular(999),
              )
            : null,
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: filled ? NuvoColors.white : context.themeColors.inkMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SearchResultList extends StatelessWidget {
  const _SearchResultList({
    required this.results,
    required this.crewState,
    required this.onAdd,
    required this.onAccept,
  });

  final List<CrewSearchResult> results;
  final CrewState crewState;
  final ValueChanged<PublicUser> onAdd;
  final ValueChanged<PublicUser> onAccept;

  @override
  Widget build(BuildContext context) {
    return _PeopleSurface(
      children: [
        for (var i = 0; i < results.length; i++)
          NuvoStaggerIn(
            index: i,
            child: _rowFor(results[i], i == results.length - 1),
          ),
      ],
    );
  }

  /// Resolve the row's action live from CrewState — the same relationship the
  /// requests list and crew list read, so a mutation here updates everywhere.
  Widget _rowFor(CrewSearchResult result, bool isLast) {
    final user = result.user;
    final status = crewState.relationshipFor(
      user.id,
      fallback: result.connectionStatus,
    );
    final busy = crewState.pendingUserIds.contains(user.id);
    // BeReal-style context — a recommendation should say why you know them.
    final subtitle = result.mutualCount > 0
        ? '${user.handleLine} · ${result.mutualCount} mutual ${result.mutualCount == 1 ? 'friend' : 'friends'}'
        : null;
    return _UserRow(
      user: user,
      subtitle: subtitle,
      added:
          status == CrewConnectionStatus.connected ||
          status == CrewConnectionStatus.pendingOutgoing,
      loading: busy,
      actionLabel: switch (status) {
        CrewConnectionStatus.connected => 'Friends',
        CrewConnectionStatus.pendingOutgoing => 'Requested',
        CrewConnectionStatus.pendingIncoming => 'Accept',
        CrewConnectionStatus.none => 'Add',
      },
      onPressed: switch (status) {
        CrewConnectionStatus.none => () => onAdd(user),
        CrewConnectionStatus.pendingIncoming => () => onAccept(user),
        _ => null,
      },
      isLast: isLast,
    );
  }
}

/// The social stage — one white card with the app's navy ink outline holding
/// the crews entry, the people, and their asks. No offset shadow.
class _SocialField extends StatelessWidget {
  const _SocialField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NuvoSpacing.pageHorizontal,
        8,
        NuvoSpacing.pageHorizontal,
        32,
      ),
      child: DecoratedBox(
        key: const ValueKey('people-card'),
        decoration: BoxDecoration(
          color: context.themeColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.card),
          border: Border.all(color: context.themeColors.border, width: 2),
        ),
        child: Padding(
          // 16 inside; tighter sides on the narrowest phones so rows keep room.
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 340 ? 6 : 16,
            16,
            MediaQuery.sizeOf(context).width < 340 ? 6 : 16,
            16,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PeopleSurface extends StatelessWidget {
  const _PeopleSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Rows live inside a quiet sheet — dividers carry the rhythm, and the
    // hairline edge keeps grouping without spending the ink border on
    // utility content.
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NuvoRadii.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(children: children),
        ),
      ),
    );
  }
}

// ── Empty + loading states ────────────────────────────────────────────────────

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.bodyMedium.copyWith(
        color: context.themeColors.inkMuted,
      ),
    );
  }
}

/// Contained placeholder rows while the member pass resolves — a contained
/// shimmer, not a full-page spinner.
class _CrewSkeleton extends StatelessWidget {
  const _CrewSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double height, {double widthFactor = 1}) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: context.themeColors.panel,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.themeColors.panel,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(12, widthFactor: 0.55),
                      const SizedBox(height: 6),
                      bar(10, widthFactor: 0.35),
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

/// The lightweight relationship surface — who this person is *to me*: how
/// often we've raced, who leads the head-to-head, the last mutual results,
/// and the two actions the relationship actually offers. Not a profile
/// page — PROFILE leaves for that.
class _PersonSheet extends StatefulWidget {
  const _PersonSheet({
    required this.member,
    required this.myId,
    required this.sharedRaces,
    required this.onRace,
    required this.onProfile,
    this.racingIn,
    this.onWatch,
    this.myInitials,
    this.myPhotoUrl,
  });

  final PublicUser member;
  final String myId;

  /// The viewer's own avatar for the rivalry side of the card.
  final String? myInitials;
  final String? myPhotoUrl;
  final List<Race> sharedRaces;
  final VoidCallback onRace;
  final VoidCallback onProfile;

  /// The active shared race they're inside right now — makes "Racing" in
  /// the strip real: the sheet leads with a Watch doorway into that race.
  final Race? racingIn;
  final VoidCallback? onWatch;

  @override
  State<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<_PersonSheet> {
  /// Which face is out: identity/relationship (front) ↔ the head-to-head
  /// competitive layer (back). The flip is the seam between the two.
  bool _showBack = false;

  void _flip() {
    NuvoHaptics.select();
    setState(() => _showBack = !_showBack);
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final first = member.displayName.split(' ').first;
    final finished =
        widget.sharedRaces.where((r) => r.status == 'completed').toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    var mine = 0;
    var theirs = 0;
    for (final r in finished) {
      final myRank = rankForUser(r, widget.myId);
      final theirRank = rankForUser(r, member.id);
      if (myRank == null || theirRank == null || myRank == theirRank) {
        continue;
      }
      if (myRank < theirRank) {
        mine++;
      } else {
        theirs++;
      }
    }
    // Best matchup — the movement we've settled most often, with its own
    // head-to-head inside it. Canonical: final standings only.
    String? matchup;
    if (finished.isNotEmpty) {
      final groups = <String, List<Race>>{};
      for (final r in finished) {
        groups.putIfAbsent(raceActivityTitle(r), () => []).add(r);
      }
      final best = groups.entries.reduce(
        (a, b) => a.value.length >= b.value.length ? a : b,
      );
      var bm = 0;
      var bt = 0;
      for (final r in best.value) {
        final myRank = rankForUser(r, widget.myId);
        final theirRank = rankForUser(r, member.id);
        if (myRank == null || theirRank == null || myRank == theirRank) {
          continue;
        }
        if (myRank < theirRank) {
          bm++;
        } else {
          bt++;
        }
      }
      matchup =
          '${best.key} · '
          '${bm > bt
              ? 'You lead $bm–$bt'
              : bt > bm
              ? '$first leads $bt–$bm'
              : 'Tied $bm–$bt'}';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NuvoSpacing.pageHorizontal,
          4,
          NuvoSpacing.pageHorizontal,
          20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stable chrome — the shell owns the drag handle (theme
            // showDragHandle); affordance and actions stay put while only
            // the card between them turns.
            NuvoFlipCard(
              height: 288,
              flipped: _showBack,
              onFlip: _flip,
              front: _PersonCardFace(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NuvoAvatar(
                      initials: member.initials,
                      photoUrl: member.profilePhotoUrl,
                      size: 72,
                      bgColor: nuvoAvatarColorFor(member.id),
                      textColor: NuvoColors.white,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: context.themeColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      member.handleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.themeColors.inkMuted,
                      ),
                    ),
                    // Nuvo Level — competitive identity, quiet chip beside
                    // the handle, same visibility rules as the profile card.
                    if (member.level != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: context.themeColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: context.themeColors.border,
                          ),
                        ),
                        child: Text(
                          'Lv. ${member.level}',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: context.blueInk,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    if (widget.racingIn != null) ...[
                      const SizedBox(height: 10),
                      PressableScale(
                        onTap: widget.onWatch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: context.themeColors.ink,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: NuvoColors.danger,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Racing now · '
                                  '${widget.racingIn!.displayTitle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.labelMedium.copyWith(
                                    // Pill fill is c.ink — page color is
                                    // the inverted foreground in both
                                    // themes (light: ice on navy, dark:
                                    // navy on near-white).
                                    color: context.themeColors.page,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: context.blueInk,
                                size: 15,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      widget.sharedRaces.isEmpty
                          ? 'No races together yet'
                          : '${widget.sharedRaces.length} '
                                '${widget.sharedRaces.length == 1 ? 'race' : 'races'} together',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: context.themeColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              back: _PersonCardFace(
                child: _PersonRivalryFace(
                  member: member,
                  first: first,
                  mine: mine,
                  theirs: theirs,
                  sharedCount: widget.sharedRaces.length,
                  matchup: matchup,
                  racingIn: widget.racingIn,
                  onWatch: widget.onWatch,
                  myId: widget.myId,
                  myInitials: widget.myInitials,
                  myPhotoUrl: widget.myPhotoUrl,
                  recent: finished.take(2).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: _showBack
                  ? 'Show $first'
                  : 'Show your rivalry with $first',
              child: NuvoPressable(
                haptic: false, // _flip fires the select haptic once
                onTap: _flip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Text(
                    _showBack ? 'About $first ↻' : 'Your matchup ↻',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: context.blueInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: NuvoPrimaryButton(
                    label: 'Race $first',
                    small: true,
                    onPressed: widget.onRace,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NuvoGhostButton(
                    label: 'Profile',
                    small: true,
                    onPressed: widget.onProfile,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The shared chrome for both faces of the person card — a signature card
/// (navy outline + hard shadow) since this is the object being flipped.
class _PersonCardFace extends StatelessWidget {
  const _PersonCardFace({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: context.themeColors.border, width: 1.5),
        boxShadow: AppShadows.hardOffset(context.themeColors.inkShadow),
      ),
      child: child,
    );
  }
}

/// The rivalry face — "your thing with this person", not a stats readout:
/// the head-to-head score is the hero, the live race is the invitation, and
/// recent results are small objects. Every number is canonical — final
/// standings and live progress only.
class _PersonRivalryFace extends StatelessWidget {
  const _PersonRivalryFace({
    required this.member,
    required this.first,
    required this.mine,
    required this.theirs,
    required this.sharedCount,
    required this.myId,
    required this.recent,
    this.matchup,
    this.racingIn,
    this.onWatch,
    this.myInitials,
    this.myPhotoUrl,
  });

  final PublicUser member;
  final String first;
  final int mine;
  final int theirs;
  final int sharedCount;
  final String myId;
  final List<Race> recent;
  final String? matchup;
  final Race? racingIn;
  final VoidCallback? onWatch;
  final String? myInitials;
  final String? myPhotoUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final racing = racingIn;
    final myP = racing?.participants.where((p) => p.userId == myId).firstOrNull;
    final theirP = racing?.participants
        .where((p) => p.userId == member.id)
        .firstOrNull;

    return Column(
      children: [
        // ── The score, as a hero ──────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RivalrySide(
              name: 'YOU',
              avatar: NuvoAvatar(
                initials: myInitials ?? 'Y',
                photoUrl: myPhotoUrl,
                size: 20,
              ),
              wins: mine,
              leading: mine > theirs,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'VS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: c.inkSubtle,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            _RivalrySide(
              name: first.toUpperCase(),
              avatar: NuvoAvatar(
                initials: member.initials,
                photoUrl: member.profilePhotoUrl,
                size: 20,
                bgColor: nuvoAvatarColorFor(member.id),
                textColor: NuvoColors.white,
              ),
              wins: theirs,
              leading: theirs > mine,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Shared history divider ────────────────────────────────────────
        Row(
          children: [
            Expanded(child: Divider(color: c.divider, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                sharedCount == 0
                    ? 'NO RACES TOGETHER YET'
                    : '$sharedCount '
                          '${sharedCount == 1 ? 'RACE' : 'RACES'} TOGETHER',
                style: AppTextStyles.labelSmall.copyWith(
                  color: c.inkMuted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(child: Divider(color: c.divider, thickness: 1)),
          ],
        ),
        const SizedBox(height: 12),

        // ── The live invitation ───────────────────────────────────────────
        if (racing != null)
          PressableScale(
            onTap: onWatch,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: NuvoColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RACING NOW · ${racing.displayTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$first ${theirP?.progressValue ?? 0} · '
                          'You ${myP?.progressValue ?? 0}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: context.blueInk,
                    size: 16,
                  ),
                ],
              ),
            ),
          )
        else if (recent.isEmpty)
          Text(
            'Race $first to start the rivalry.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
          )
        else if (matchup != null)
          Text(
            'Best matchup · $matchup',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
          ),

        // ── Recent matchups as objects ────────────────────────────────────
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'RECENT MATCHUPS',
              style: AppTextStyles.labelSmall.copyWith(
                color: c.inkMuted,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 2),
          for (final race in recent)
            _PersonRecentRow(
              race: race,
              myId: myId,
              memberId: member.id,
              first: first,
            ),
        ],
      ],
    );
  }
}

/// One side of the score hero — avatar + name over the win count; gold
/// marks whoever currently leads.
class _RivalrySide extends StatelessWidget {
  const _RivalrySide({
    required this.name,
    required this.avatar,
    required this.wins,
    required this.leading,
  });

  final String name;
  final Widget avatar;
  final int wins;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatar,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(
                  color: c.inkMuted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$wins',
          style: AppTextStyles.number(
            30,
            color: leading ? NuvoColors.gold : c.ink,
            weight: FontWeight.w800,
          ),
        ),
        Text(
          'wins',
          style: AppTextStyles.labelSmall.copyWith(color: c.inkMuted),
        ),
      ],
    );
  }
}

/// One settled mutual result — "[trophy] {first} beat you · Title · 2h".
/// Ranks come from the server's final standings, never recomputed locally.
class _PersonRecentRow extends StatelessWidget {
  const _PersonRecentRow({
    required this.race,
    required this.myId,
    required this.memberId,
    required this.first,
  });

  final Race race;
  final String myId;
  final String memberId;
  final String first;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final myRank = rankForUser(race, myId);
    final theirRank = rankForUser(race, memberId);
    final String outcome;
    final bool won;
    if (myRank == null || theirRank == null) {
      outcome = 'Finished';
      won = false;
    } else if (myRank < theirRank) {
      outcome = 'You beat $first';
      won = true;
    } else if (theirRank < myRank) {
      outcome = '$first beat you';
      won = false;
    } else {
      outcome = 'Dead heat';
      won = false;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            Icons.emoji_events_rounded,
            size: 15,
            color: won ? NuvoColors.gold : c.inkSubtle,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              outcome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${race.displayTitle} · ${notificationRelativeTime(DateTime.tryParse(race.updatedAt)?.toUtc() ?? DateTime.now().toUtc())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(color: c.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
