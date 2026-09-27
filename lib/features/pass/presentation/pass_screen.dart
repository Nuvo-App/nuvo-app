import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_flip_card.dart';
import '../../../core/widgets/nuvo_live_race_card.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_ripple_surface.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/nuvo_stagger_in.dart';
import '../../../data/models/user_profile.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../../crew/data/crew_api.dart'
    show ConnectOutcome, CrewConnectionStatus, CrewSearchResult;
import '../../crew/domain/crew_presence.dart';
import '../../notifications/application/notification_controller.dart';
import '../../notifications/data/notification_models.dart';
import '../../notifications/domain/notification_display.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../races/presentation/create_race_screen.dart'
    show RaceCreatePrefill;
import '../../social/data/crew_activity.dart';
import '../../social/domain/nuvo_destination.dart';
import 'package:go_router/go_router.dart';

class PassScreen extends ConsumerStatefulWidget {
  const PassScreen({super.key});

  @override
  ConsumerState<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends ConsumerState<PassScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  PassInfo? _passInfo;
  List<CrewSearchResult> _results = const [];
  bool _loading = true;
  bool _searching = false;
  bool _searchOpen = false;
  String? _error;
  String? _searchError;

  /// Feed tabs: 0 For you · 1 Activity · 2 Races.
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
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (isPresentationDemoUser(ref.read(authControllerProvider).user)) {
        if (mounted) {
          setState(() {
            _passInfo = presentationDemoPassInfo();
            _loading = false;
          });
        }
        return;
      }
      final pass = await ref
          .read(authControllerProvider.notifier)
          .getMemberPass();
      // Crew + requests are owned by CrewController (docs/agents/18) — it
      // auto-loads on auth and revalidates on tab focus (MainShell); this
      // screen only reads it via ref.watch in build().
      if (mounted) {
        setState(() {
          _passInfo = pass;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      // A demo session must never surface a network error — if the session
      // resolved as presentation mode mid-flight, fixtures win.
      if (isPresentationDemoUser(ref.read(authControllerProvider).user)) {
        setState(() {
          _passInfo = presentationDemoPassInfo();
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = 'Could not load your crew.';
        _loading = false;
      });
    }
  }

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
      memberId: _passInfo?.memberId ?? '-',
      passSlug: _passInfo?.passSlug,
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
          const SnackBar(content: Text('Could not add this crew member.')),
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

  /// Inbox categories that are inherently 'For you' — a reaction lands on
  /// something of mine, an invite asks me to join. They merge into the
  /// For-you tab from the notification inbox (canonical race_events never
  /// produce them, so there's no event/item duplication).
  static const _meCategories = {
    'crew_request',
    'crew_request_accepted',
    'crew_connected',
    'reaction',
    'race_invite',
  };

  /// Inbox rows that merge into For you — the two social asks that have no
  /// race_event counterpart.
  static const _forYouNoteCategories = {'reaction', 'race_invite'};

  CrewActivityItem _itemFromNotification(NuvoNotification n) {
    return CrewActivityItem(
      id: 'ntf:${n.id}',
      type: n.category,
      occurredAt: n.createdAt,
      actor: n.actorName == null
          ? null
          : CrewActivityActor(
              id: '',
              displayName: n.actorName!,
              profilePhotoUrl: n.actorPhotoUrl,
            ),
      raceId: n.destination is RaceDestination
          ? (n.destination as RaceDestination).raceId
          : null,
      title: n.title,
      summary: n.body,
      destination: n.destination,
      read: n.read,
    );
  }

  bool _isForYou(CrewActivityItem item, String myId, Map<String, Race> byId) {
    if (_meCategories.contains(item.type)) return true;
    if (item.involvesUser(myId)) return true;
    // A live race I'm in belongs in For you — the spectator payload names
    // the viewer explicitly.
    if (item.type == 'race_live') {
      return item.live?.participants.any((p) => p.isMe) ?? false;
    }
    // "Your race started/finished" — membership check via the race cache:
    // feed events also cover crew-only races I'm not in, and those aren't
    // mine.
    if (item.type == 'race_started' || item.type == 'race_finished') {
      return byId[item.raceId]?.isParticipant(myId) ?? false;
    }
    return false;
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
    final racingIn = shared
        .where((r) => r.status == 'active')
        .firstOrNull;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NuvoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _PersonSheet(
        member: member,
        myId: myId,
        sharedRaces: shared,
        racingIn: racingIn,
        onRace: () {
          Navigator.of(sheetContext).pop();
          context.push(
            '/races/new',
            extra: RaceCreatePrefill(
              idea: 'First to 100 Pushups',
              withUser: member,
            ),
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

  /// "Race {person}" — the social suggestion: straight into the composer
  /// with that member attached, same as the person sheet's RACE action.
  void _raceMember(PublicUser member) {
    context.push(
      '/races/new',
      extra: RaceCreatePrefill(
        idea: 'First to 100 Pushups',
        withUser: member,
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
          return _PostAction(
            label: 'Rematch',
            onTap: () => _rematch(item),
          );
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
            extra: RaceCreatePrefill(
              idea: 'First to 100 Pushups',
              withUser: _personFor(actor, ref.read(crewControllerProvider).members),
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
        return _PostAction(
          label: 'Join race',
          onTap: () => _joinRace(item),
        );
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
    final id = raceId ??
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

  /// Run it back — one tap on a finished shared race. Real sessions use
  /// the server's one-step rematch (clones settings + roster). Demo mode
  /// can't call the network, so it opens the composer prefilled with the
  /// top crew opponent instead — same product result.
  Future<void> _runItBack(Race race) async {
    const key = 'run-it-back';
    if (!_ctaBusy.add(key)) return;
    try {
      final user = ref.read(authControllerProvider).user;
      if (isPresentationDemoUser(user)) {
        final crew = ref.read(crewControllerProvider).members;
        final opponent = race.participants
            .where((p) => p.userId != user?.id)
            .toList()
          ..sort((a, b) => b.progressValue.compareTo(a.progressValue));
        PublicUser? member;
        for (final p in opponent) {
          member = crew.where((m) => m.id == p.userId).firstOrNull;
          if (member != null) break;
        }
        if (mounted) {
          context.push(
            '/races/new',
            extra: RaceCreatePrefill(
              idea: race.displayTitle,
              withUser: member,
            ),
          );
        }
        return;
      }
      final next =
          await ref.read(raceControllerProvider.notifier).rematchRace(race.id);
      if (mounted) context.push('/race/${next.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start the rematch.")),
        );
      }
    } finally {
      if (mounted) setState(() => _ctaBusy.remove(key));
    }
  }

  Future<void> _rematch(CrewActivityItem item) async {
    final id = item.raceId;
    if (id == null || !_ctaBusy.add(item.id)) return;
    try {
      final race =
          await ref.read(raceControllerProvider.notifier).rematchRace(id);
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
    final sharedRaces = allRaces
        .where(
          (r) => r.status == 'active' && crewIds.any(r.isParticipant),
        )
        .toList()
      ..sort((a, b) {
        int crewCount(Race r) =>
            r.participants.where((p) => crewIds.contains(p.userId)).length;
        return crewCount(b).compareTo(crewCount(a));
      });
    final finishedRaces = allRaces
        .where(
          (r) => r.status == 'completed' && crewIds.any(r.isParticipant),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // The Races tab's time hierarchy — LIVE → ACTIVE → UP NEXT → RECENT —
    // reads the same canonical truth as the feed: `race_live` items are the
    // server's live spectator payload (they also surface in For you), and
    // 'scheduled' is the server's effective status for a future start line.
    // A race already rendering as a live card is skipped from Active — one
    // race, one presentation.
    final liveItems = activityState.items
        .where((i) => i.live != null)
        .toList();
    final liveRaceIds = {
      for (final i in liveItems)
        if (i.raceId != null) i.raceId!,
    };
    final activeRaces =
        sharedRaces.where((r) => !liveRaceIds.contains(r.id)).toList();
    final upcomingRaces = allRaces
        .where(
          (r) =>
              r.status == 'scheduled' &&
              crewIds.any(r.isParticipant),
        )
        .toList()
      ..sort(
        (a, b) => (a.startLineAt ?? '').compareTo(b.startLineAt ?? ''),
      );
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
    // For you — direct events landing on me (passed me, my race, my
    // result) plus the two inbox asks that never produce a race_event
    // (reactions to mine, race invites). Live races are always For you —
    // a crew member racing right now is inherently relevant.
    final notifItems = ref.watch(notificationControllerProvider).items;
    final forYouItems = [
      ...feedItems.where(
        (i) => i.live == null && _isForYou(i, myId, racesById),
      ),
      for (final n in notifItems)
        if (_forYouNoteCategories.contains(n.category))
          _itemFromNotification(n),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    // Everything else in the stream — the relevance surface shows it at
    // micro/standard weight under the direct events, so For you never
    // collapses to a blank canvas while the crew is doing anything.
    final forYouIds = {for (final i in forYouItems) i.id};
    final restOfFeed = feedItems
        .where((i) => i.live == null && !forYouIds.contains(i.id))
        .toList();
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

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              NuvoBottomNav.bottomPadding(context),
            ),
            children: [
              // ── Header ───────────────────────────────────────────────────
              _CrewHeader(
                subtitle: crew.isEmpty
                    ? 'Find people to race with.'
                    : 'Your people, all in one place',
                onMyCode: () => context.push('/my-nuvo'),
                searchOpen: _searchOpen,
                onToggleSearch: () =>
                    setState(() => _searchOpen = !_searchOpen),
              ),

              // ── Search expands inline from the header icon — a tool that
              // opens when needed, not a section competing with the people.
              if (_searchOpen) ...[
                const SizedBox(height: 12),
                Row(
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
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SearchResultList(
                    results: _results,
                    crewState: crewState,
                    onAdd: _addCrew,
                    onAccept: _acceptRequest,
                  ),
                ] else if (_searchError != null && !_searching) ...[
                  const SizedBox(height: 16),
                  NuvoPressable(
                    onTap: () => _onSearchChanged(_searchController.text),
                    haptic: false,
                    child: _EmptyNote(text: _searchError!),
                  ),
                ] else if (_searchController.text.trim().length >= 2 &&
                    !_searching) ...[
                  const SizedBox(height: 16),
                  const _EmptyNote(text: 'No matching Nuvo members found.'),
                ],
              ],
              const SizedBox(height: 14),

              // ── Loading ──────────────────────────────────────────────────
              if (_loading)
                const _CrewSkeleton()
              // ── Error ────────────────────────────────────────────────────
              else if (_error != null)
                NuvoErrorState(message: _error!, onRetry: _refreshAll)
              // ── Content ──────────────────────────────────────────────────
              else ...[
                // ── The people — flattened, no container card: You, the
                // faces ordered by who's around, Add. Status pills carry
                // the one thing worth knowing under each person — Racing
                // beats Active, absence says nothing.
                _PeopleStrip(
                  me: profile,
                  members: crewOrdered,
                  racingIds: racingIds,
                  hotIds: hotIds,
                  onYou: () => context.push('/my-nuvo'),
                  onPerson: _openPerson,
                  onAdd: () => context.push('/crew/add'),
                ),

                // ── Empty crew — the void below the strip becomes the two
                // things that actually fill it: find people, share your code.
                if (crew.isEmpty) ...[
                  const SizedBox(height: 18),
                  _PeopleSurface(
                    children: [
                      _ActionRow(
                        icon: Icons.person_search_rounded,
                        title: 'Find people',
                        subtitle: 'Name, @username or member code',
                        onTap: () => context.push('/crew/add'),
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

                // ── Requests — people knocking, compressed to utility
                // weight: one surface, single-line rows, inline actions.
                // Incoming first — an ask aimed at me outranks one I sent.
                if (requests.isNotEmpty || outgoing.isNotEmpty) ...[
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

                // ── A quiet lens switch — text under a hairline, not a
                // segmented control claiming the page. Everything above
                // this row is geometrically identical across all three
                // tabs: switching only ever changes what's below.
                const SizedBox(height: 16),
                _CrewTabs(
                  selected: _feedTab,
                  onSelect: (i) => setState(() => _feedTab = i),
                  counts: [
                    forYouItems.length + liveItems.length,
                    null,
                    liveItems.length +
                        activeRaces.length +
                        upcomingRaces.length,
                  ],
                ),
                const SizedBox(height: 12),

                if (crewState.error != null && crew.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: NuvoErrorState(
                      message: crewState.error!,
                      onRetry: () => ref
                          .read(crewControllerProvider.notifier)
                          .load(force: true),
                    ),
                  ),
                if (activityState.error != null && feedItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: NuvoErrorState(
                      message: activityState.error!,
                      onRetry: () => ref
                          .read(crewActivityProvider.notifier)
                          .load(force: true),
                    ),
                  ),

                switch (_feedTab) {
                  0 => _ForYouTab(
                      liveItems: liveItems,
                      directItems: forYouItems,
                      restOfFeed: restOfFeed,
                      activeRaces: activeRaces,
                      upcomingRaces: upcomingRaces,
                      finishedRaces: finishedRaces,
                      crew: crew,
                      myId: myId,
                      racesById: racesById,
                      reactingIds: activityState.reactingItemIds,
                      busyIds: _ctaBusy,
                      emptyNote:
                          'Nothing happening yet — find people to race with.',
                      onTap: _openCrewActivity,
                      onPerson: (i) => _tapFeedPerson(i, crew),
                      onReact: _react,
                      actionFor: (i) => _actionFor(i, myId, racesById),
                      onOpenRace: (r) => context.push('/race/${r.id}'),
                      onRaceMember: _raceMember,
                      onNewRace: () => context.push('/races/new'),
                      onRunItBack: _runItBack,
                      runItBackBusy: _ctaBusy.contains('run-it-back'),
                    ),
                  1 => _FeedColumn(
                      items: feedItems,
                      reactingIds: activityState.reactingItemIds,
                      crew: crew,
                      myId: myId,
                      racesById: racesById,
                      busyIds: _ctaBusy,
                      emptyNote:
                          'No crew activity yet — races, finishes and personal bests from your people land here.',
                      onTap: _openCrewActivity,
                      onPerson: (i) => _tapFeedPerson(i, crew),
                      onReact: _react,
                      actionFor: (i) => _actionFor(i, myId, racesById),
                    ),
                  _ => _RacesTab(
                      liveItems: liveItems,
                      ongoing: activeRaces,
                      upcoming: upcomingRaces,
                      finished: finishedRaces,
                      myId: myId,
                      crewIds: crewIds,
                      reactingIds: activityState.reactingItemIds,
                      onOpen: (r) => context.push('/race/${r.id}'),
                      onOpenLive: _openCrewActivity,
                      onReact: _react,
                    ),
                },
              ],
            ],
          ),
        ),
      ),
    );
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
    return Column(
      children: [
        for (var i = 0; i < ordered.length; i++)
          NuvoStaggerIn(
            index: i,
            child: _feedTile(
              ordered[i],
              level: _feedLevelOf(ordered[i], myId, racesById),
              race: racesById[ordered[i].raceId],
              myId: myId,
              busy: reactingIds.contains(ordered[i].id),
              action: actionFor(ordered[i]),
              actionBusy: busyIds.contains(ordered[i].id),
              onTap: onTap,
              onPerson: onPerson,
              onReact: onReact,
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

/// The emotional register of a moment — the feed is a room, not a table,
/// so competitive, achievement, and ask moments carry different ink.
enum _MomentTone { competitive, achievement, ask, standard }

_MomentTone _toneOf(CrewActivityItem item, String myId) {
  switch (item.type) {
    case 'rank_changed':
    case 'lead_changed':
      return item.involvesUser(myId)
          ? _MomentTone.competitive
          : _MomentTone.standard;
    case 'personal_best':
    case 'participant_finished':
    case 'race_finished':
    case 'winner_determined':
      return _MomentTone.achievement;
    case 'race_invite':
    case 'rematch_requested':
      return _MomentTone.ask;
    default:
      return _MomentTone.standard;
  }
}

/// One feed item at its earned level — micro row, live card, or post card.
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
      onTap: () => onTap(item),
      onReact: (emoji) => onReact(item, emoji),
    );
  }
  return _SocialPostCard(
    item: item,
    race: race,
    myId: myId,
    prominent: level == 1,
    tone: _toneOf(item, myId),
    busy: busy,
    action: action,
    actionBusy: actionBusy,
    onTap: () => onTap(item),
    onPerson: () => onPerson(item),
    onReact: (emoji) => onReact(item, emoji),
  );
}

/// For you — a relevance surface, not a filtered inbox. Ordered by what
/// matters in my crew right now: live races, events aimed at me, the races
/// we're inside, then the crew's recent activity. It only says "nothing"
/// when the user genuinely has no crew content; a crew member with no
/// races and no activity still gets a real next step (race someone).
/// For you — a composed surface, not a filtered inbox. Independent
/// modules, each collapsing on its own: the live moment, the races we
/// share, the crew's social stream, and the standing invitation to race
/// someone. Nothing renders an empty canvas just because the feed is
/// quiet — relationships and races are content too.
class _ForYouTab extends StatelessWidget {
  const _ForYouTab({
    required this.liveItems,
    required this.directItems,
    required this.restOfFeed,
    required this.activeRaces,
    required this.upcomingRaces,
    required this.finishedRaces,
    required this.crew,
    required this.myId,
    required this.racesById,
    required this.reactingIds,
    required this.busyIds,
    required this.emptyNote,
    required this.onTap,
    required this.onPerson,
    required this.onReact,
    required this.actionFor,
    required this.onOpenRace,
    required this.onRaceMember,
    required this.onNewRace,
    required this.onRunItBack,
    required this.runItBackBusy,
  });

  /// Live `race_live` items — they head this surface (the room's pulse)
  /// and stay below the tab bar so switching tabs never moves the bar.
  final List<CrewActivityItem> liveItems;
  final List<CrewActivityItem> directItems;

  /// Feed items not already surfaced as direct/live — the crew's general
  /// activity, shown at micro/standard weight under the direct events.
  final List<CrewActivityItem> restOfFeed;
  final List<Race> activeRaces;
  final List<Race> upcomingRaces;

  /// Recently finished shared races — the quiet state still shows real
  /// history when nothing is happening right now.
  final List<Race> finishedRaces;
  final List<PublicUser> crew;
  final String myId;
  final Map<String, Race> racesById;
  final Set<String> reactingIds;
  final Set<String> busyIds;
  final String emptyNote;
  final ValueChanged<CrewActivityItem> onTap;
  final ValueChanged<CrewActivityItem> onPerson;
  final void Function(CrewActivityItem item, String emoji) onReact;
  final _PostAction? Function(CrewActivityItem item) actionFor;
  final ValueChanged<Race> onOpenRace;

  /// "Race {person}" — opens the composer with that member attached
  /// (same path as the person sheet's RACE action).
  final ValueChanged<PublicUser> onRaceMember;

  /// The bare composer — the secondary "start a race" doorway.
  final VoidCallback onNewRace;

  /// One-tap rematch on the most recent shared race.
  final ValueChanged<Race> onRunItBack;
  final bool runItBackBusy;

  @override
  Widget build(BuildContext context) {
    final direct = [...directItems]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final rest = [...restOfFeed]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final social = [...direct, ...rest];
    final crewIds = {for (final m in crew) m.id};

    Widget tile(CrewActivityItem item) => _feedTile(
          item,
          level: _feedLevelOf(item, myId, racesById),
          race: racesById[item.raceId],
          myId: myId,
          busy: reactingIds.contains(item.id),
          action: actionFor(item),
          actionBusy: busyIds.contains(item.id),
          onTap: onTap,
          onPerson: onPerson,
          onReact: onReact,
        );

    // Modules compose independently — a quiet tab is a populated page
    // with fewer modules, never a different product.
    final hasLive = liveItems.isNotEmpty;
    final hasRacing = activeRaces.isNotEmpty || upcomingRaces.isNotEmpty;
    final hasSocial = social.isNotEmpty;
    final hasRecent = finishedRaces.isNotEmpty;
    if (!hasLive &&
        !hasRacing &&
        !hasSocial &&
        !hasRecent &&
        crew.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: _EmptyNote(text: emptyNote),
      );
    }

    // The centerpiece has to EARN its size. Live `race_live` items already
    // own the top slot; beneath them the only warranted hero is an active
    // head-to-head I'm inside — a chase happening now. A finished race is
    // history, not a hero: it renders at result weight in the lists below.
    // Empty space is better than manufactured importance.
    final hero = hasLive ? null : _heroRaceFor(activeRaces, myId);
    final racingBelow = hero == null
        ? activeRaces
        : activeRaces.where((r) => r.id != hero.id).toList();
    // The newest finished race is the rematch candidate — its own module.
    // Showing it again as the first row of recent history would be the
    // same race twice in adjacent sections, so recent history is the rest.
    final rematch = hasRecent ? finishedRaces.first : null;
    final recentBelow = rematch == null
        ? finishedRaces
        : finishedRaces.where((r) => r.id != rematch.id).toList();

    var stagger = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A — the room's pulse: live crew races head the surface. Keyed on
        // the canonical item id: a newly-arrived live card enters (rise +
        // fade) and displaced cards travel — every real insertion is seen.
        if (liveItems.isNotEmpty)
          NuvoReorderColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < liveItems.length && i < 2; i++)
                NuvoStaggerIn(
                  key: ValueKey(liveItems[i].id),
                  index: stagger++,
                  child: tile(liveItems[i]),
                ),
            ],
          ),

        // A2 — the social centerpiece when nothing is live: the race
        // I'm chasing, or the last result's consequence.
        if (hero != null)
          NuvoStaggerIn(
            index: stagger++,
            child: _CrewHeroCard(
              race: hero,
              myId: myId,
              onTap: () => onOpenRace(hero),
            ),
          ),

        // B — the quick action surface: the crew is always the next move.
        if (crew.isNotEmpty) ...[
          const SizedBox(height: 6),
          const _SectionLabel(label: 'Start a race'),
          const SizedBox(height: 8),
          _RaceCrewChips(
            members: crew.take(5).toList(),
            onRaceMember: onRaceMember,
          ),
          const SizedBox(height: 6),
          NuvoPressable(
            onTap: onNewRace,
            haptic: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'New race →',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],

        // C — the social layer: direct moments first, then the stream.
        // Same keyed insertion contract as section A — keys follow the
        // canonical item id, so a provider refresh reorders/inserts
        // physically instead of the bottom slot popping in.
        if (hasSocial) ...[
          const SizedBox(height: 6),
          const _SectionLabel(label: 'From your crew'),
          const SizedBox(height: 8),
          NuvoReorderColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < social.length && i < 9; i++)
                NuvoStaggerIn(
                  key: ValueKey(social[i].id),
                  index: stagger++,
                  child: tile(social[i]),
                ),
            ],
          ),
        ],

        // D — the competition layer: shared races are content even when
        // the feed has nothing new to say. The hero's race is already
        // above — it doesn't repeat here.
        if (racingBelow.isNotEmpty || upcomingRaces.isNotEmpty) ...[
          const SizedBox(height: 6),
          const _SectionLabel(label: 'Racing with your crew'),
          const SizedBox(height: 8),
          for (final race in racingBelow.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ActiveRaceCard(
                race: race,
                myId: myId,
                crewIds: crewIds,
                onTap: () => onOpenRace(race),
              ),
            ),
          if (upcomingRaces.isNotEmpty)
            _PeopleSurface(
              children: [
                for (var i = 0; i < upcomingRaces.length && i < 2; i++)
                  _UpNextRaceRow(
                    race: upcomingRaces[i],
                    crewIds: crewIds,
                    isLast: i == upcomingRaces.length - 1 || i == 1,
                    onTap: () => onOpenRace(upcomingRaces[i]),
                  ),
              ],
            ),
        ],

        // E — shared history, people-first: who beat whom, my placement.
        // Social feed weight — avatar + outcome rows directly on the page,
        // no enclosing sheet pretending results are settings.
        if (recentBelow.isNotEmpty) ...[
          const SizedBox(height: 6),
          const _SectionLabel(label: 'Recently with your crew'),
          const SizedBox(height: 4),
          for (var i = 0; i < recentBelow.length && i < 3; i++)
            _FinishedRaceRow(
              race: recentBelow[i],
              myId: myId,
              isLast: i == recentBelow.length - 1 || i == 2,
              onTap: () => onOpenRace(recentBelow[i]),
            ),
        ],

        // F — the continuation: run the latest shared race back.
        if (rematch != null) ...[
          const SizedBox(height: 6),
          const _SectionLabel(label: 'Run it back'),
          const SizedBox(height: 6),
          _RunItBackRow(
            race: rematch,
            myId: myId,
            busy: runItBackBusy,
            onTap: () => onRunItBack(rematch),
          ),
        ],
      ],
    );
  }
}

/// Picks For-you's centerpiece race — but only a genuinely current one:
/// an active race I'm inside with someone else in it. A race my crew runs
/// without me is their moment, not my hero (it lists below); a race I'm
/// running alone is progress, not a head-to-head. Returns null when no
/// shared chase is live — the page does not manufacture one.
Race? _heroRaceFor(List<Race> active, String myId) {
  if (active.isEmpty) return null;
  final mine = active
      .where(
        (r) => r.participantFor(myId) != null && r.participants.length > 1,
      )
      .toList();
  if (mine.isEmpty) return null;
  // Stakes order: chasing a lead (tightest gap first) > dead even >
  // defending a lead > racing alone. Consequence reads best when
  // there's someone ahead to catch.
  double stakes(Race r) {
    final ranked = serverRankedParticipants(r);
    final me = r.participantFor(myId);
    if (ranked.isEmpty || me == null) return double.infinity;
    final leader = ranked.first;
    if (leader.userId == myId) return ranked.length > 1 ? 2.0 : 3.0;
    final target = (r.targetValue ?? 0) > 0 ? r.targetValue!.toDouble() : 1;
    final gap = (leader.progressValue - me.progressValue).abs() / target;
    return leader.progressValue == me.progressValue ? 1.0 : gap;
  }

  mine.sort((a, b) => stakes(a).compareTo(stakes(b)));
  return mine.first;
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
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
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

    // Who I'm measured against: the leader while I chase, the runner-up
    // while I lead; when I'm not in the race, it's the top pair.
    final left = me ?? leader;
    final right = me == null
        ? (ranked.length > 1 ? ranked[1] : null)
        : (leader.userId == myId
            ? (ranked.length > 1 ? ranked[1] : null)
            : leader);

    // The consequence line — plain words, colored by what it means for me.
    final status = _statusLine(
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
          border: Border.all(color: NuvoColors.navy, width: 1.5),
          boxShadow: AppShadows.hardSmall,
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
                    style: AppTextStyles.labelUppercase(
                      10,
                      color: c.inkSubtle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _HeroRacer(
                    participant: left,
                    isMe: left.userId == myId,
                    highlight: left.userId == leader.userId,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    right == null
                        ? raceScoreLabel(race, left.progressValue)
                        : '${left.progressValue} — ${right.progressValue}',
                    style: AppTextStyles.number(
                      22,
                      color: c.ink,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                if (right != null)
                  Expanded(
                    child: _HeroRacer(
                      participant: right,
                      isMe: right.userId == myId,
                      highlight: right.userId == leader.userId,
                    ),
                  )
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              status.text,
              style: AppTextStyles.labelMedium.copyWith(
                color: status.color,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Divider(height: 1, thickness: 1, color: c.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                Text(
                  finished ? 'See result' : 'See race',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: NuvoColors.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ({String text, Color color}) _statusLine({
    required bool finished,
    required RaceParticipant? me,
    required RaceParticipant left,
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
        text:
            '${_firstName(leader.displayName)} took it · you placed #$rank',
        color: NuvoColors.textMuted,
      );
    }

    if (me == null) {
      return (
        text: right == null
            ? '${_firstName(leader.displayName)} is racing'
            : '${_firstName(leader.displayName)} in front',
        color: NuvoColors.textMuted,
      );
    }

    final ctx = race.viewerContext;
    final leading = ctx?.isLeading ?? leader.userId == myId;
    final tied = ctx?.isTied ??
        (right != null && right.progressValue == me.progressValue);
    final gap =
        ctx?.gapToLeader?.abs() ??
        (right != null ? (right.progressValue - me.progressValue).abs() : 0);

    if (tied) {
      return (text: 'Dead even', color: NuvoColors.blue);
    }
    if (leading) {
      return (text: "You're in front", color: NuvoColors.gold);
    }
    if (right == null || gap <= 0) {
      return (text: 'On the start line', color: NuvoColors.textMuted);
    }
    return (
      text: '${raceScoreLabel(race, gap)} behind',
      color: NuvoColors.blue,
    );
  }
}

/// One side of the hero matchup — avatar, name, nothing else. Gold ring
/// marks who's in front; "You" replaces my name.
class _HeroRacer extends StatelessWidget {
  const _HeroRacer({
    required this.participant,
    required this.isMe,
    required this.highlight,
  });

  final RaceParticipant participant;
  final bool isMe;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Column(
      children: [
        NuvoAvatar(
          initials: _CrewHeroCard._initialsFor(participant.displayName),
          size: NuvoAvatarSizes.md,
          photoUrl: participant.profilePhotoUrl,
          borderColor: highlight ? NuvoColors.gold : c.divider,
          borderWidth: highlight ? 2 : 1.5,
        ),
        const SizedBox(height: 6),
        Text(
          isMe ? 'You' : _CrewHeroCard._firstName(participant.displayName),
          style: AppTextStyles.labelSmall.copyWith(
            color: isMe ? NuvoColors.blue : c.ink,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Compact person chips — avatar + first name + bolt — the shared
/// "race this person" affordance used by For you's Race-someone module
/// and the quiet-crew composition.
class _RaceCrewChips extends StatelessWidget {
  const _RaceCrewChips({
    required this.members,
    required this.onRaceMember,
  });

  final List<PublicUser> members;
  final ValueChanged<PublicUser> onRaceMember;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in members)
          PressableScale(
            onTap: () => onRaceMember(m),
            child: Container(
              padding: const EdgeInsets.only(
                left: 4,
                right: 10,
                top: 4,
                bottom: 4,
              ),
              decoration: BoxDecoration(
                color: NuvoColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: NuvoColors.divider,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NuvoAvatar(
                    initials: m.initials,
                    photoUrl: m.profilePhotoUrl,
                    size: 28,
                    bgColor: nuvoAvatarColorFor(m.id),
                    textColor: NuvoColors.white,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    m.displayName.split(' ').first,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.bolt_rounded,
                    color: NuvoColors.blue,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Run it back — the competitive continuation: the latest shared race's
/// top opponent, what it was, and a one-tap Rematch. Uses the server's
/// rematch path in real sessions, composer prefill in demo.
class _RunItBackRow extends StatelessWidget {
  const _RunItBackRow({
    required this.race,
    required this.myId,
    required this.busy,
    required this.onTap,
  });

  final Race race;
  final String myId;
  final bool busy;
  final VoidCallback onTap;

  static String _initialsFor(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'N';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final opponents = race.participants
        .where((p) => p.userId != myId)
        .toList()
      ..sort((a, b) => b.progressValue.compareTo(a.progressValue));
    final top = opponents.firstOrNull;
    final ago = notificationRelativeTime(
      DateTime.tryParse(race.updatedAt)?.toUtc() ?? DateTime.now().toUtc(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (top != null)
            NuvoAvatar(
              initials: _initialsFor(top.displayName),
              photoUrl: top.profilePhotoUrl,
              size: 32,
              bgColor: nuvoAvatarColorFor(top.userId),
              textColor: NuvoColors.white,
            )
          else
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: NuvoColors.panel,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.replay_rounded,
                color: NuvoColors.navy,
                size: 16,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  top != null
                      ? 'You vs ${top.displayName.split(' ').first}'
                      : race.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${race.displayTitle} · $ago',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PressableScale(
            onTap: busy ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: NuvoColors.blue,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                busy ? '…' : 'Rematch',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: NuvoPressable(
        onTap: item.destination == null ? null : onTap,
        haptic: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              NuvoPressable(
                onTap: item.actor == null ? null : onPerson,
                scale: 0.94,
                haptic: false,
                child: NuvoAvatar(
                  initials: notificationInitials(item.actor?.displayName),
                  photoUrl: item.actor?.profilePhotoUrl,
                  size: 26,
                  bgColor: nuvoAvatarColorFor(item.id),
                  textColor: NuvoColors.white,
                ),
              ),
              const SizedBox(width: 10),
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
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                notificationRelativeTime(item.occurredAt),
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The person-centric feed card. The avatar/name lead, the headline says
/// what they did, and the race is context — never the other way around.
class _SocialPostCard extends StatelessWidget {
  const _SocialPostCard({
    required this.item,
    required this.race,
    required this.myId,
    required this.prominent,
    required this.tone,
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

  /// Level 1 chrome — the offset shadow + strong edge, reserved for
  /// moments that land on me. Level 2 gets the quiet divider-color edge.
  final bool prominent;

  /// The moment's register — competitive moments carry blue ink,
  /// achievements carry warm gold, asks carry the navy edge.
  final _MomentTone tone;
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

  /// The middle of the card — the fact the event carries, rendered as a
  /// muted panel. Only the event types with a real artifact get one.
  Widget? _contextBlock() {
    switch (item.type) {
      case 'rank_changed':
        final overtaken = item.payload['overtakenUserIds'];
        final passedMe = overtaken is List && overtaken.contains(myId);
        if (!passedMe) return null;
        // "Riley 67 · You 62" from live standings when the race is cached;
        // the rank is the honest fallback.
        if (race != null) {
          final standings = serverRankedParticipants(race!);
          final actor = standings
              .where((p) => p.userId == item.actor?.id)
              .firstOrNull;
          final me = standings.where((p) => p.userId == myId).firstOrNull;
          if (actor != null && me != null) {
            // One compact competitive line, not a two-row panel.
            return _PostContext(
              lines: [
                '${actor.displayName.split(' ').first} ${actor.progressValue}  ·  You ${me.progressValue}',
              ],
            );
          }
        }
        final rank = (item.payload['newRank'] as num?)?.toInt();
        if (rank != null) {
          return _PostContext(lines: ['Now #$rank ahead of you']);
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
        return _PostContext(
          lines: [
            '$score${race?.metric != null ? ' ${race!.metric!.toUpperCase()}' : ''}',
            if (rank != null) rank == 1 ? '🏆 1ST' : '#$rank',
          ],
        );
      case 'personal_best':
        final best = (item.payload['newBest'] as num?)?.toInt();
        final prev = (item.payload['previousBest'] as num?)?.toInt();
        if (best == null) return null;
        final delta = prev != null ? best - prev : null;
        final metric = (item.payload['metric'] as String?)?.toUpperCase();
        return _PostContext(
          lines: [
            '$best${metric != null ? ' $metric' : ''}${delta != null && delta > 0 ? '  ↗ +$delta' : ''}',
          ],
        );
      case 'race_finished':
      case 'winner_determined':
        final score = (item.payload['score'] as num?)?.toInt() ??
            (item.payload['topScore'] as num?)?.toInt();
        return _PostContext(
          lines: [
            if (item.payload['winnerUserId'] == myId) '🏆 YOU WON',
            if (score != null) 'Top score $score',
          ]..removeWhere((s) => s.isEmpty),
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

  @override
  Widget build(BuildContext context) {
    final contextBlock = _contextBlock();
    const radius = NuvoRadii.card;
    // The room speaks in registers, not one stamp: a pass is a blue
    // competitive flash, a best or a win carries warm gold, an ask keeps
    // the navy edge, and ordinary activity stays white and quiet.
    final Color bg;
    final Color edge;
    switch (tone) {
      case _MomentTone.competitive:
        bg = NuvoColors.blueSurface;
        edge = NuvoColors.blue;
      case _MomentTone.achievement:
        bg = NuvoColors.warningSurface;
        edge = prominent ? NuvoColors.warning : NuvoColors.warningBorder;
      case _MomentTone.ask:
        bg = NuvoColors.surface;
        edge = prominent ? NuvoColors.navy : NuvoColors.divider;
      case _MomentTone.standard:
        bg = NuvoColors.surface;
        edge = prominent ? NuvoColors.navy : NuvoColors.divider;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          // The ink outline + offset shadow is a priority signal now —
          // reserved for moments that land on me. Ordinary activity gets a
          // hairline so the feed stops looking like one stack of stamps.
          border: Border.all(color: edge, width: prominent ? 1.5 : 1),
          boxShadow: prominent ? AppShadows.hardSmall : null,
        ),
        child: NuvoPressable(
          onTap: item.destination == null ? null : onTap,
          haptic: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    NuvoPressable(
                      onTap: onPerson,
                      scale: 0.94,
                      haptic: false,
                      child: NuvoAvatar(
                        initials:
                            notificationInitials(item.actor?.displayName),
                        photoUrl: item.actor?.profilePhotoUrl,
                        size: 36,
                        bgColor: nuvoAvatarColorFor(item.id),
                        textColor: NuvoColors.white,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: NuvoPressable(
                        onTap: onPerson,
                        haptic: false,
                        child: Text(
                          item.actor?.displayName ?? 'Nuvo member',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: NuvoColors.navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      notificationRelativeTime(item.occurredAt),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    if (!item.read)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: NuvoColors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 45),
                  child: Text(
                    _headline(),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                if (contextBlock != null) ...[
                  const SizedBox(height: 8),
                  contextBlock,
                ],
                if (item.isReactionable || action != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 45),
                    child: Row(
                      children: [
                        if (item.isReactionable)
                          _ReactionBar(
                            item: item,
                            busy: busy,
                            onReact: onReact,
                          ),
                        const Spacer(),
                        if (action != null)
                          PressableScale(
                            onTap: actionBusy ? null : action!.onTap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: prominent
                                    ? NuvoColors.blue
                                    : NuvoColors.blueSurface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: NuvoColors.blue,
                                  width: prominent ? 1.5 : 1.2,
                                ),
                              ),
                              child: Text(
                                actionBusy ? '…' : action!.label,
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: prominent
                                      ? NuvoColors.white
                                      : NuvoColors.blue,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
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

/// The muted fact panel inside a post — scores, a result, a PB. One or two
/// centered lines; the card's only non-copy element.
class _PostContext extends StatelessWidget {
  const _PostContext({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 45),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: NuvoColors.panel,
        borderRadius: BorderRadius.circular(NuvoRadii.sm),
      ),
      child: Column(
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.navy,
                  fontWeight: FontWeight.w800,
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
  /// "For you 3" means there are three things actually inside.
  final List<int?> counts;

  static const _labels = ['For you', 'Activity', 'Races'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: NuvoColors.divider, width: 1),
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
                            ? NuvoColors.navy
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: selected == i
                                ? NuvoColors.navy
                                : NuvoColors.muted,
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
                                ? NuvoColors.blue
                                : NuvoColors.textDim,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
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

/// The Races lens — a time hierarchy over the races my crew is competing
/// in: LIVE → HAPPENING NOW → UP NEXT → RECENT. Live races render the same
/// canonical `_LiveRaceCard` the feed uses (same `race_live` payload, same
/// truth) and are deduped out of Active; every section collapses entirely
/// when it has nothing to say.
class _RacesTab extends StatelessWidget {
  const _RacesTab({
    required this.liveItems,
    required this.ongoing,
    required this.upcoming,
    required this.finished,
    required this.myId,
    required this.crewIds,
    required this.reactingIds,
    required this.onOpen,
    required this.onOpenLive,
    required this.onReact,
  });

  /// Feed items carrying a `race_live` spectator payload — the same items
  /// For-you surfaces; the tab just projects live state first.
  final List<CrewActivityItem> liveItems;
  final List<Race> ongoing;
  final List<Race> upcoming;
  final List<Race> finished;
  final String myId;
  final Set<String> crewIds;
  final Set<String> reactingIds;
  final ValueChanged<Race> onOpen;
  final ValueChanged<CrewActivityItem> onOpenLive;
  final void Function(CrewActivityItem item, String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    if (liveItems.isEmpty &&
        ongoing.isEmpty &&
        upcoming.isEmpty &&
        finished.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: _EmptyNote(
          text:
              'No shared races yet — start one with your crew from Compete.',
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
          const _SectionLabel(label: 'Happening now'),
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

        // ── Up next — scheduled races with a real start line.
        if (upcoming.isNotEmpty) ...[
          if (liveItems.isNotEmpty || ongoing.isNotEmpty)
            const SizedBox(height: 6),
          const _SectionLabel(label: 'Up next'),
          const SizedBox(height: 8),
          _PeopleSurface(
            children: [
              for (var i = 0; i < upcoming.length && i < 4; i++)
                _UpNextRaceRow(
                  race: upcoming[i],
                  crewIds: crewIds,
                  isLast: i == upcoming.length - 1 || i == 3,
                  onTap: () => onOpen(upcoming[i]),
                ),
            ],
          ),
        ],

        // ── Recent — settled races read as people/outcomes, not titles.
        if (finished.isNotEmpty) ...[
          const SizedBox(height: 6),
          const _SectionLabel(label: 'Recent'),
          const SizedBox(height: 4),
          for (var i = 0; i < finished.length && i < 6; i++)
            _FinishedRaceRow(
              race: finished[i],
              myId: myId,
              isLast: i == finished.length - 1 || i == 5,
              onTap: () => onOpen(finished[i]),
            ),
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
        Text(
          'Live now',
          style: AppTextStyles.sectionTitle,
        ),
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
    final leader = standings.firstOrNull;
    final fill = leader == null
        ? 0.0
        : (leader.progressPercent / 100).clamp(0.0, 1.0);
    final crewCount =
        standings.where((p) => crewIds.contains(p.userId)).length;
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
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.card),
          border: Border.all(color: NuvoColors.divider, width: 1),
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
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (daysLeft != null)
                  Text(
                    daysLeft,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.muted,
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
                      const TextSpan(
                        text: '  ·  ',
                        style: TextStyle(color: NuvoColors.muted),
                      ),
                    TextSpan(
                      text: top[i].userId == myId ? 'You' : top[i].displayName.split(' ').first,
                      style: TextStyle(
                        color: NuvoColors.navy,
                        fontWeight: top[i].userId == myId
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: ' ${raceScoreLabel(race, top[i].progressValue)}',
                      style: TextStyle(
                        color: top[i].userId == myId
                            ? NuvoColors.blue
                            : NuvoColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: NuvoColors.trackBg),
                    FractionallySizedBox(
                      widthFactor: fill,
                      alignment: Alignment.centerLeft,
                      child: Container(color: NuvoColors.blue),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    {
                      '$crewCount from your crew',
                      '${race.participants.length} racing',
                    }.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: NuvoColors.blue,
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

/// A scheduled shared race — who I'm meeting and when, one compact line.
class _UpNextRaceRow extends StatelessWidget {
  const _UpNextRaceRow({
    required this.race,
    required this.crewIds,
    required this.isLast,
    required this.onTap,
  });

  final Race race;
  final Set<String> crewIds;
  final bool isLast;
  final VoidCallback onTap;

  String _startsIn() {
    final start = DateTime.tryParse(race.startLineAt ?? '');
    if (start == null) return 'Starting soon';
    final diff = start.difference(DateTime.now());
    if (diff.inMinutes <= 0) return 'Starting soon';
    if (diff.inHours < 1) return 'Starts in ${diff.inMinutes}m';
    if (diff.inDays < 1) {
      return 'Starts in ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    return 'Starts in ${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    // Mini avatar cluster — the crew faces in this race.
    final crewIn = race.participants
        .where((p) => crewIds.contains(p.userId))
        .take(3)
        .toList();
    return Column(
      children: [
        NuvoPressable(
          onTap: onTap,
          haptic: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: crewIn.isEmpty ? 0 : 20.0 + (crewIn.length - 1) * 14,
                  height: 24,
                  child: Stack(
                    children: [
                      for (var i = 0; i < crewIn.length; i++)
                        Positioned(
                          left: i * 14.0,
                          child: NuvoAvatar(
                            initials: _rowInitials(crewIn[i].displayName),
                            photoUrl: crewIn[i].profilePhotoUrl,
                            size: 24,
                            bgColor:
                                nuvoAvatarColorFor(crewIn[i].userId),
                            textColor: NuvoColors.white,
                          ),
                        ),
                    ],
                  ),
                ),
                if (crewIn.isNotEmpty) const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        race.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          _startsIn(),
                          '${race.participants.length} joined',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: NuvoColors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, color: NuvoColors.divider),
      ],
    );
  }

  static String _rowInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'N';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// A settled shared race — people first: the winner's face and outcome
/// lead, my placement is the subline, the race is context. Not a title +
/// date row.
class _FinishedRaceRow extends StatelessWidget {
  const _FinishedRaceRow({
    required this.race,
    required this.myId,
    required this.isLast,
    required this.onTap,
  });

  final Race race;
  final String myId;
  final bool isLast;
  final VoidCallback onTap;

  static String _initialsFor(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'N';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final standings = race.finalStandings;
    final winner = standings.where((s) => s.rank == 1).firstOrNull;
    final runnerUp = standings.where((s) => s.rank == 2).firstOrNull;
    final mine = standings.where((s) => s.userId == myId).firstOrNull;
    final iWon = mine?.rank == 1;
    final resultLine = mine == null
        ? null
        : iWon
            ? race.displayTitle
            : 'You finished #${mine.rank} · ${race.displayTitle}';
    final outcome = winner == null
        ? race.displayTitle
        : iWon
            ? (runnerUp != null
                ? 'You beat ${runnerUp.displayName.split(' ').first}'
                : 'You won ${race.displayTitle}')
            : mine?.rank == 2
                ? '${winner.displayName.split(' ').first} beat you'
                : '${winner.displayName.split(' ').first} won · ${race.displayTitle}';
    return Column(
      children: [
        NuvoPressable(
          onTap: onTap,
          haptic: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                if (winner != null) ...[
                  NuvoAvatar(
                    initials: _initialsFor(winner.displayName),
                    photoUrl: winner.profilePhotoUrl,
                    size: 28,
                    bgColor: nuvoAvatarColorFor(winner.userId),
                    textColor: NuvoColors.white,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        iWon ? '🏆 $outcome' : outcome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        [
                          ?resultLine,
                          notificationRelativeTime(
                            DateTime.tryParse(race.updatedAt)?.toUtc() ??
                                DateTime.now().toUtc(),
                          ),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: iWon
                              ? NuvoColors.successOn
                              : NuvoColors.muted,
                          fontWeight:
                              iWon ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: NuvoColors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          // Past the 28px avatar + gap — the separator aligns to the text
          // column, the leading column's edge, not the page edge.
          const Divider(
            height: 1,
            indent: 38,
            color: NuvoColors.divider,
          ),
      ],
    );
  }
}

/// The reaction strip — 🔥 👏 💪 chips with aggregate counts. Mine is
/// highlighted; tapping toggles it. Tactile: each chip scales on press and
/// pops with a light haptic (fired by the caller).
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.item,
    required this.busy,
    required this.onReact,
  });

  final CrewActivityItem item;
  final bool busy;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final code in kReactionEmojis)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: _ReactionChip(
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
  });

  final String glyph;
  final int count;
  final bool mine;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A zero-count chip is just the emoji button — a bordered pill around
    // nothing reads as decoration competing with the event.
    final bare = count == 0 && !mine;
    return PressableScale(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        padding: EdgeInsets.symmetric(
          horizontal: bare ? 4 : 7,
          vertical: 3,
        ),
        decoration: bare
            ? null
            : BoxDecoration(
                color: mine ? NuvoColors.blueSurface : NuvoColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: mine ? NuvoColors.blue : NuvoColors.divider,
                  width: mine ? 1.3 : 1,
                ),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The glyph pops when canonical state flips mine on — a full
            // pop on add, a quieter half-pop on remove.
            NuvoPop(
              trigger: mine,
              intensity: mine ? 1.0 : 0.5,
              child: Text(glyph, style: const TextStyle(fontSize: 12)),
            ),
            if (count > 0) ...[
              const SizedBox(width: 3),
              NuvoNumberFlow(
                value: count,
                duration: const Duration(milliseconds: 220),
                style: AppTextStyles.labelSmall.copyWith(
                  color: mine ? NuvoColors.blue : NuvoColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
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
            Text('Crew', style: AppTextStyles.screenTitle),
            const Spacer(),
            Semantics(
              button: true,
              label: searchOpen ? 'Close search' : 'Find people',
              child: NuvoRippleSurface(
                onTap: onToggleSearch,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    searchOpen
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    color: searchOpen ? NuvoColors.blue : NuvoColors.navy,
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
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.qr_code_rounded,
                    color: NuvoColors.navy,
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
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
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
                      : crewPresenceFor(m.lastActiveAt) ==
                              CrewPresence.active
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
                color: NuvoColors.panel,
                shape: BoxShape.circle,
                border: NuvoBorders.quiet,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                color: NuvoColors.navy,
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
            width: 50,
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
                    color: NuvoColors.navy,
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
    final (dot, word, ink) = switch (status) {
      _StripStatus.racing => (NuvoColors.blue, 'Racing', NuvoColors.blue),
      _StripStatus.hot => (NuvoColors.warning, '🔥', NuvoColors.warningOn),
      _StripStatus.active => (
          NuvoColors.success,
          'Active',
          NuvoColors.successOn,
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hot)
          Flexible(
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: AppTextStyles.labelSmall.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
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
  });

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
                    color: NuvoColors.panel,
                    borderRadius: BorderRadius.circular(NuvoRadii.md),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: NuvoColors.navy, size: 20),
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
                          color: NuvoColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionLabel != null)
                  Text(
                    actionLabel!,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: NuvoColors.muted,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: NuvoColors.border.withValues(alpha: 0.7),
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
            color: NuvoColors.white,
            borderRadius: BorderRadius.circular(NuvoRadii.md),
            border: Border.all(color: NuvoColors.border, width: 2),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.qr_code_scanner_rounded,
            color: NuvoColors.navy,
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
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? user.handleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
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
                            color: NuvoColors.textMuted,
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
            color: NuvoColors.border.withValues(alpha: 0.7),
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
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.card),
        border: Border.all(color: NuvoColors.divider, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NuvoRadii.card - 1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              if (incoming.isNotEmpty) ...[
                _RequestGroupLabel(
                  label: 'Crew requests',
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
          ? const BoxDecoration(
              border: Border(
                top: BorderSide(color: NuvoColors.divider, width: 1),
              ),
            )
          : null,
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.blue,
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
                color: NuvoColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _MiniAction(
            label: 'Decline',
            onTap: busy ? null : onDecline,
          ),
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
                color: NuvoColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'Pending',
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          PressableScale(
            onTap: busy ? null : onCancel,
            child: const SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                Icons.close_rounded,
                color: NuvoColors.muted,
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
        padding: EdgeInsets.symmetric(
          horizontal: filled ? 12 : 8,
          vertical: 6,
        ),
        decoration: filled
            ? BoxDecoration(
                color: NuvoColors.blue,
                borderRadius: BorderRadius.circular(999),
              )
            : null,
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: filled ? NuvoColors.white : NuvoColors.muted,
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
        ? '${user.handleLine} · ${result.mutualCount} mutual crew'
        : null;
    return _UserRow(
      user: user,
      subtitle: subtitle,
      added: status == CrewConnectionStatus.connected ||
          status == CrewConnectionStatus.pendingOutgoing,
      loading: busy,
      actionLabel: switch (status) {
        CrewConnectionStatus.connected => 'In crew',
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
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.card),
        border: Border.all(color: NuvoColors.divider, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NuvoRadii.card - 1),
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
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
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
              color: NuvoColors.panel,
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
                    color: NuvoColors.panel,
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
  });

  final PublicUser member;
  final String myId;
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
    final finished = widget.sharedRaces
        .where((r) => r.status == 'completed')
        .toList()
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stable chrome — handle, affordance, and actions never move;
            // only the card between them turns.
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: NuvoColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
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
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      member.handleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
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
                            color: NuvoColors.navy,
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
                                    color: NuvoColors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: NuvoColors.blueLight,
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
                              '${widget.sharedRaces.length == 1
                                  ? 'race'
                                  : 'races'} together',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              back: _PersonCardFace(
                child: finished.isEmpty
                    ? Center(
                        child: Text(
                          widget.racingIn != null
                              ? 'In a race together now — settle it first.'
                              : 'No races together yet — start one.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: NuvoColors.muted,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${first.toUpperCase()} VS YOU',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: NuvoColors.muted,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$theirs — $mine',
                            style: AppTextStyles.number(
                              26,
                              color: NuvoColors.navy,
                              weight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '$first wins — your wins',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: NuvoColors.muted,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${widget.sharedRaces.length} shared '
                            '${widget.sharedRaces.length == 1
                                ? 'race'
                                : 'races'}'
                            '${widget.racingIn != null
                                ? ' · racing together now'
                                : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: NuvoColors.muted,
                            ),
                          ),
                          if (matchup != null)
                            Text(
                              'Best matchup · $matchup',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            'RECENT',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: NuvoColors.muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          for (final race in finished.take(2))
                            _PersonRecentRow(
                              race: race,
                              myId: widget.myId,
                              memberId: member.id,
                              first: first,
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: _showBack
                  ? 'Show identity'
                  : 'Show competitive stats',
              child: NuvoPressable(
                haptic: false, // _flip fires the select haptic once
                onTap: _flip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Text(
                    _showBack ? 'About ↻' : 'Stats ↻',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.blue,
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
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: NuvoColors.navy, width: 1.5),
        boxShadow: AppShadows.hardSmall,
      ),
      child: child,
    );
  }
}

/// One settled mutual result — "{first} beat you · Title · 2h". Ranks come
/// from the server's final standings, never recomputed locally.
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
    final myRank = rankForUser(race, myId);
    final theirRank = rankForUser(race, memberId);
    final String outcome;
    if (myRank == null || theirRank == null) {
      outcome = 'Finished';
    } else if (myRank < theirRank) {
      outcome = 'You beat $first';
    } else if (theirRank < myRank) {
      outcome = '$first beat you';
    } else {
      outcome = 'Dead heat';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              outcome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${race.displayTitle} · ${notificationRelativeTime(
              DateTime.tryParse(race.updatedAt)?.toUtc() ??
                  DateTime.now().toUtc(),
            )}',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}
