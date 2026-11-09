// The v13 Crew tab — the social home: your crews, who's racing right now,
// friend requests, the friends-activity feed, friends' crews and friends.
//
// Route contract: mounted by the shell at '/pass' (the Crew tab) and
// reachable as '/crew'. No path or query params; `extra` is ignored.
//
// Spec: PROTOTYPE_V13_SPEC.md "Crew tab" · mapping CREW_SOCIAL.md §1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nuvo/core/config/nuvo_flags.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';

import 'crew_tab_v13_widgets.dart';
import '../../../tour/tour_anchors.dart';
import '../../../tour/tour_controller.dart';

/// "Your friends' crews" (W2 `GET /squads/discover`). Returns null whenever
/// the call can't produce rows — the section hides, never errors the tab.
final crewDiscoverProvider =
    FutureProvider.autoDispose<List<CrewDiscoverItem>?>((ref) async {
      if (!NuvoFlags.crews.value) return null;
      try {
        return await ref.read(squadRepositoryProvider).discover();
      } catch (_) {
        return null;
      }
    });

class CrewTabV13Screen extends ConsumerStatefulWidget {
  const CrewTabV13Screen({super.key});

  @override
  ConsumerState<CrewTabV13Screen> createState() => _CrewTabV13ScreenState();
}

class _CrewTabV13ScreenState extends ConsumerState<CrewTabV13Screen> {
  /// Crew ids I already asked to join this session (requested state survives
  /// discover refetches).
  final Set<String> _requestedCrewIds = {};
  final Set<String> _joinBusyCrewIds = {};

  @override
  void initState() {
    super.initState();
    // Same self-kick the shell gives tabs — keeps the screen live when it is
    // mounted as a plain route (and inside tests).
    Future(() {
      ref.read(crewControllerProvider.notifier).revalidate();
      ref.read(squadControllerProvider.notifier).revalidate();
      ref.read(crewActivityProvider.notifier).revalidate();
      ref.read(raceControllerProvider.notifier).revalidate();
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(crewDiscoverProvider);
    await Future.wait([
      ref.read(crewControllerProvider.notifier).load(),
      ref.read(squadControllerProvider.notifier).refresh(),
      ref.read(crewActivityProvider.notifier).load(),
      ref.read(raceControllerProvider.notifier).loadRaces(),
    ]);
  }

  Future<void> _startCrew() async {
    CrewGroup? created;
    final done = await showV13Sheet<bool>(
      context,
      builder: (_) => CrewInputSheet(
        title: 'Start a crew',
        hint: 'Crew name',
        buttonLabel: 'Create crew',
        onSubmit: (name) async {
          try {
            created = await ref
                .read(squadControllerProvider.notifier)
                .create(name);
            return null;
          } on ApiException catch (e) {
            return e.statusCode >= 500
                ? "Couldn't start the crew. Try again."
                : e.message;
          } catch (_) {
            return "Couldn't start the crew. Try again.";
          }
        },
      ),
    );
    final crew = created;
    if (done == true && mounted && crew != null) {
      showV13Toast(context, 'Your crew is live.');
      context.push('/crews/${crew.id}');
    }
  }

  Future<void> _joinCrew() async {
    final done = await showV13Sheet<bool>(
      context,
      builder: (_) => CrewInputSheet(
        title: 'Join with a code',
        hint: 'Crew code',
        buttonLabel: 'Join crew',
        upperCase: true,
        onSubmit: (code) async {
          try {
            await ref.read(squadControllerProvider.notifier).join(code);
            return null;
          } on ApiException catch (e) {
            return e.statusCode >= 500
                ? "Couldn't join. Try again."
                : e.message;
          } catch (_) {
            return "That code didn't work. Check it and try again.";
          }
        },
      ),
    );
    if (done == true && mounted) {
      showV13Confetti(context);
      showV13Toast(context, "You're in the crew.");
    }
  }

  Future<void> _acceptRequest(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).acceptRequest(user);
      if (!mounted) return;
      V13Haptics.confirm();
      showV13Confetti(context);
      showV13Toast(
        context,
        "You're friends with ${user.displayName.split(' ').first}.",
      );
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't accept. Try again.");
    }
  }

  Future<void> _declineRequest(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).declineRequest(user);
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't decline. Try again.");
    }
  }

  Future<void> _cancelOutgoing(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).remove(user.id);
      if (mounted) showV13Toast(context, 'Request cancelled.');
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't cancel. Try again.");
    }
  }

  Future<void> _askToJoin(CrewDiscoverItem crew) async {
    setState(() => _joinBusyCrewIds.add(crew.id));
    try {
      await ref.read(squadRepositoryProvider).joinRequest(crew.id);
      if (!mounted) return;
      setState(() {
        _joinBusyCrewIds.remove(crew.id);
        _requestedCrewIds.add(crew.id);
      });
      showV13Toast(context, 'Request sent.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _joinBusyCrewIds.remove(crew.id));
      showV13Toast(context, "Couldn't send the request. Try again.");
    }
  }

  Future<void> _cheer(CrewActivityItem item) async {
    final ok = await ref
        .read(crewActivityProvider.notifier)
        .toggleReaction(item, 'fire');
    if (!ok && mounted) {
      showV13Toast(context, "Couldn't cheer right now. Try again.");
    }
  }

  void _openFeedItem(CrewActivityItem item) {
    final location =
        item.destination?.location ??
        (item.raceId != null ? '/race/${item.raceId}' : null);
    if (location != null) context.push(location);
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authControllerProvider).user?.id ?? '';
    final crewState = ref.watch(crewControllerProvider);
    final squadState = ref.watch(squadControllerProvider);
    final feedState = ref.watch(crewActivityProvider);
    final raceState = ref.watch(raceControllerProvider);
    final discover = ref.watch(crewDiscoverProvider);

    // Racing right now — a crew member inside one of my active shared races
    // earns a slot; the richest-shared race leads the order.
    final crewIds = {for (final m in crewState.members) m.id};
    int crewCount(Race r) =>
        r.participants.where((p) => crewIds.contains(p.userId)).length;
    final sharedRaces =
        raceState.races
            .where((r) => r.status == 'active' && crewIds.any(r.isParticipant))
            .toList()
          ..sort((a, b) => crewCount(b).compareTo(crewCount(a)));
    final membersById = {for (final m in crewState.members) m.id: m};
    final racing = <({PublicUser user, Race race})>[];
    final racingSeen = <String>{};
    for (final race in sharedRaces) {
      for (final p in race.participants) {
        final user = membersById[p.userId];
        if (user != null && racingSeen.add(user.id)) {
          racing.add((user: user, race: race));
        }
      }
    }

    return ColoredBox(
      color: V13.bg,
      child: RefreshIndicator(
        color: V13.blue,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: V13TabBar.bottomPadding(context)),
          children: [
            V13TopBar(
              title: 'Crew',
              trailing: [
                V13IconButton(
                  key: ref.watch(tourActiveProvider)
                      ? TourAnchors.keyOf(TourAnchor.myNuvoCode)
                      : null,
                  icon: Icons.qr_code_2,
                  semanticLabel: 'My Nuvo code',
                  onTap: () => context.push('/my-nuvo'),
                ),
                V13Button.secondary(
                  label: 'Add friend',
                  size: V13ButtonSize.small,
                  icon: Icons.person_add_alt_1,
                  onPressed: () => openScan(context),
                ),
              ],
            ),
            const SizedBox(height: V13.gapXxl),
            _crewsSection(squadState),
            const SizedBox(height: V13.gapSection),
            if (crewState.loading && !crewState.hasData)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    V13Skeleton.line(width: 160, height: 24),
                    SizedBox(height: V13.gapMd),
                    V13Skeleton.box(width: double.infinity, height: 96),
                  ],
                ),
              )
            else if (crewState.error != null && !crewState.hasData)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: CrewSectionError(
                  message: "Couldn't load your friends",
                  onRetry: () =>
                      ref.read(crewControllerProvider.notifier).load(),
                ),
              )
            else ...[
              if (racing.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
                  child: V13SectionHeader(title: 'Racing right now'),
                ),
                const SizedBox(height: V13.gapMd),
                SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: V13.pagePad,
                    ),
                    itemCount: racing.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: V13.gapMd),
                    itemBuilder: (context, i) => RacingFriendCell(
                      name: racing[i].user.displayName,
                      photoUrl: racing[i].user.profilePhotoUrl,
                      race: racing[i].race,
                      onTap: () => openPerson(context, ref, racing[i].user.id),
                    ),
                  ),
                ),
              ],
              for (final user in crewState.requests.take(5)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                  child: FriendRequestCard(
                    user: user,
                    onPersonTap: () => openPerson(context, ref, user.id),
                    mutuals: crewState.mutuals[user.id],
                    busy: crewState.pendingUserIds.contains(user.id),
                    onAccept: () => _acceptRequest(user),
                    onDecline: () => _declineRequest(user),
                  ),
                ),
                const SizedBox(height: V13.gapMd),
              ],
              for (final user in crewState.outgoing.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                  child: OutgoingRequestRow(
                    user: user,
                    onPersonTap: () => openPerson(context, ref, user.id),
                    busy: crewState.pendingUserIds.contains(user.id),
                    onCancel: () => _cancelOutgoing(user),
                  ),
                ),
            ],
            if (crewState.loading ||
                crewState.error != null ||
                crewState.members.isNotEmpty)
              const SizedBox(height: V13.gapSection),
            if (!crewState.loading &&
                crewState.error == null &&
                crewState.members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: V13EmptyHero(
                  color: V13.lilac,
                  art: const V13QrPreview(),
                  artHeight: 128,
                  title: 'Racing is better together',
                  body: 'Share your code and friends join your races.',
                  ctaLabel: 'Share my code',
                  ctaIcon: Icons.ios_share_rounded,
                  onCta: () => context.push('/my-nuvo'),
                  linkLabel: 'Add friend',
                  onLink: () => openScan(context),
                ),
              )
            else ...[
              _feedSection(feedState, myId),
              _friendsCrewsSection(discover),
              const SizedBox(height: V13.gapSection),
              _friendsSection(crewState),
            ],
          ],
        ),
      ),
    );
  }

  Widget _crewsSection(SquadState squadState) {
    return ValueListenableBuilder<bool>(
      valueListenable: NuvoFlags.crews,
      builder: (context, crewsOn, _) {
        if (!crewsOn) return const SizedBox.shrink();
        final groups = squadState.groups ?? const <CrewGroup>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: V13SectionHeader(
                title: squadState.hasData
                    ? 'Your crews · ${groups.length}'
                    : 'Your crews',
              ),
            ),
            const SizedBox(height: V13.gapMd),
            if (squadState.loading && !squadState.hasData)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: V13Skeleton.box(width: double.infinity, height: 120),
              )
            else if (squadState.error != null && !squadState.hasData)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: CrewSectionError(
                  message: "Couldn't load your crews",
                  onRetry: () =>
                      ref.read(squadControllerProvider.notifier).refresh(),
                ),
              )
            else ...[
              for (final (i, crew) in groups.indexed) ...[
                V13StaggerIn(
                  key: ValueKey('crew-${crew.id}'),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V13.pagePad,
                    ),
                    child: CrewGroupCard(
                      crew: crew,
                      onTap: () => context.push('/crews/${crew.id}'),
                    ),
                  ),
                ),
                const SizedBox(height: V13.gapMd),
              ],
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: V13.pagePad,
                    vertical: V13.gapSm,
                  ),
                  child: Text(
                    'No crews yet — start one or join with a code.',
                    style: V13.caption,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: V13Card.dashed(
                  onTap: _startCrew,
                  semanticLabel: 'Start a crew',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, size: 20, color: V13.navy),
                      const SizedBox(width: V13.gapSm),
                      Text('Start a crew', style: V13.bodyStrong),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: V13ListRow(
                  leading: const V13IconTile(
                    icon: Icons.key,
                    color: V13.sky,
                    size: 40,
                  ),
                  title: 'Join with a code',
                  subtitle: 'Got a crew code from a friend?',
                  trailing: const Icon(Icons.chevron_right, color: V13.muted),
                  onTap: _joinCrew,
                  showDivider: false,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _feedSection(CrewActivityState feedState, String myId) {
    final items = feedState.items.take(15).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
          child: V13SectionHeader(title: 'What your crew is doing'),
        ),
        const SizedBox(height: V13.gapXs),
        if (feedState.loading && !feedState.hasData)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: Column(
              children: [
                SizedBox(height: V13.gapMd),
                V13Skeleton.line(width: double.infinity, height: 44),
                SizedBox(height: V13.gapMd),
                V13Skeleton.line(width: double.infinity, height: 44),
              ],
            ),
          )
        else if (feedState.error != null && !feedState.hasData)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: CrewSectionError(
              message: "Couldn't load your friends' activity",
              onRetry: () => ref.read(crewActivityProvider.notifier).load(),
            ),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: V13.gapMd),
                Text(
                  'Race with your friends — their proof, wins and badges land here.',
                  style: V13.body.copyWith(color: V13.muted),
                ),
                const SizedBox(height: V13.gapMd),
                V13Button.secondary(
                  label: 'Start a race',
                  size: V13ButtonSize.small,
                  icon: Icons.flag,
                  onPressed: () => context.push('/races/new'),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const V13Divider(),
                  FeedItemRow(
                    item: items[i],
                    onPersonTap: items[i].actor == null
                        ? null
                        : () => openPerson(context, ref, items[i].actor!.id),
                    myId: myId,
                    reactBusy: feedState.reactingItemIds.contains(items[i].id),
                    onTap: () => _openFeedItem(items[i]),
                    onCheer: items[i].isReactionable
                        ? () => _cheer(items[i])
                        : null,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _friendsCrewsSection(AsyncValue<List<CrewDiscoverItem>?> discover) {
    final crews = discover.valueOrNull;
    if (crews == null || crews.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: V13.gapSection),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
          child: V13SectionHeader(title: "Your friends' crews"),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
          child: Column(
            children: [
              for (var i = 0; i < crews.length; i++) ...[
                if (i > 0) const V13Divider(),
                DiscoverCrewRow(
                  crew: crews[i],
                  requested:
                      crews[i].requested ||
                      _requestedCrewIds.contains(crews[i].id),
                  busy: _joinBusyCrewIds.contains(crews[i].id),
                  onTap: () => context.push('/crews/${crews[i].id}'),
                  onAskToJoin: () => _askToJoin(crews[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _friendsSection(CrewState crewState) {
    final members = crewState.members;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V13SectionHeader(
            title: members.isEmpty ? 'Friends' : 'Friends · ${members.length}',
            trailingLabel: 'See all',
            onTrailingTap: () => context.push('/crew/add'),
          ),
          V13ListRow(
            leading: members.isNotEmpty
                ? V13FaceStack(
                    faces: [
                      for (final m in members.take(3))
                        V13FaceInfo(
                          id: m.id,
                          photoUrl: m.profilePhotoUrl,
                          name: m.displayName,
                        ),
                    ],
                    total: members.length,
                    size: 30,
                  )
                : const V13IconTile(
                    icon: Icons.people_outline,
                    color: V13.lilac,
                    size: 40,
                  ),
            title: members.isEmpty ? 'Add your first friend' : 'Your friends',
            subtitle: members.isEmpty
                ? 'Friends are who you race against'
                : 'Search, requests and removing friends live here',
            trailing: const Icon(Icons.chevron_right, color: V13.muted),
            onTap: () => context.push('/crew/add'),
            showDivider: false,
          ),
        ],
      ),
    );
  }
}
