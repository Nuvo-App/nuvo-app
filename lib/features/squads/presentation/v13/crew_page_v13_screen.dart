// The v13 Crew page — one crew's home: header, "Start a crew race", stats,
// the This week / All time leaderboard, recurring races, crew battle and the
// members grid.
//
// Route contract: `/crews/:id` → [crewId] is the `:id` path parameter.
// `extra` is unused.
//
// Spec: PROTOTYPE_V13_SPEC.md "Crew page" · mapping CREW_SOCIAL.md §2.
// W2 additive sections (weekly standings, recurring, battle, join requests,
// preview for non-members) hide whenever the payload/endpoint is absent.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/social/presentation/v13/crew_tab_v13_widgets.dart';
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';

import 'crew_page_v13_widgets.dart';

/// Weekly standings (W2 `GET /squads/:id/standings?period=week`). Null means
/// the endpoint doesn't exist — the period switch hides and the page keeps
/// the all-time rows from the detail payload.
final crewWeekStandingsProvider = FutureProvider.autoDispose
    .family<List<CrewGroupStanding>?, String>((ref, crewId) async {
      try {
        return await ref
            .read(squadRepositoryProvider)
            .standings(crewId, period: 'week');
      } on ApiException catch (e) {
        if (e.statusCode == 404 || e.statusCode == 405 || e.statusCode == 403) {
          return null;
        }
        rethrow;
      }
    });

/// What a non-member sees (W2 `GET /squads/:id/preview`). Null when the
/// endpoint — or the crew — doesn't exist; the page then shows its error.
final crewPreviewProvider = FutureProvider.autoDispose
    .family<CrewGroupPreview?, String>((ref, crewId) async {
      try {
        return await ref.read(squadRepositoryProvider).preview(crewId);
      } catch (_) {
        return null;
      }
    });

class CrewPageV13Screen extends ConsumerStatefulWidget {
  const CrewPageV13Screen({super.key, required this.crewId});

  /// The `:id` path parameter from `/crews/:id`.
  final String crewId;

  @override
  ConsumerState<CrewPageV13Screen> createState() => _CrewPageV13ScreenState();
}

class _CrewPageV13ScreenState extends ConsumerState<CrewPageV13Screen> {
  /// 0 = This week, 1 = All time (leaderboard segment).
  int _period = 0;

  /// Ask-to-join state for the non-member preview.
  bool _requested = false;
  bool _joinBusy = false;

  /// Session-local mute state — falls back to the payload's `muted` until I
  /// toggle it here.
  bool? _muted;

  /// Optimistic auto-join values per recurring-race id + in-flight writes.
  final Map<String, bool> _autoJoin = {};
  final Set<String> _autoJoinBusy = {};

  @override
  void initState() {
    super.initState();
    Future(
      () =>
          ref.read(squadControllerProvider.notifier).loadDetail(widget.crewId),
    );
  }

  bool _mutedFor(CrewGroup g) => _muted ?? g.muted;

  Future<void> _refresh() async {
    ref.invalidate(crewWeekStandingsProvider(widget.crewId));
    await ref
        .read(squadControllerProvider.notifier)
        .refreshDetail(widget.crewId);
  }

  void _startRace(CrewGroupDetail detail) {
    context.push(
      '/races/new',
      extra: RaceCreatePrefill(
        crewId: widget.crewId,
        crewName: detail.group.name,
      ),
    );
  }

  Future<void> _menu(CrewGroupDetail detail) async {
    final g = detail.group;
    final muted = _mutedFor(g);
    final picked = await showV13ActionSheet<String>(
      context,
      title: g.name,
      actions: [
        if (g.canManage)
          const V13SheetAction(
            label: 'Crew settings',
            value: 'settings',
            icon: Icons.settings_outlined,
          ),
        if (g.canManage && detail.joinRequests.isNotEmpty)
          V13SheetAction(
            label: 'Join requests · ${detail.joinRequests.length}',
            value: 'requests',
            icon: Icons.person_add_alt_1,
          ),
        const V13SheetAction(
          label: 'Share crew',
          value: 'share',
          icon: Icons.share_outlined,
        ),
        const V13SheetAction(
          label: 'Copy invite link',
          value: 'copy',
          icon: Icons.link,
        ),
        V13SheetAction(
          label: muted ? 'Unmute crew' : 'Mute crew',
          value: 'mute',
          icon: muted ? Icons.volume_up_outlined : Icons.volume_off_outlined,
        ),
        const V13SheetAction(
          label: 'Leave crew',
          value: 'leave',
          icon: Icons.logout,
          destructive: true,
        ),
      ],
    );
    if (!mounted || picked == null) return;
    switch (picked) {
      case 'settings':
        context.push('/crews/${widget.crewId}/settings');
      case 'requests':
        _showJoinRequests();
      case 'share':
        _shareCrew(g);
      case 'copy':
        _copyInvite(g);
      case 'mute':
        _toggleMute(g, muted);
      case 'leave':
        _leave(g);
    }
  }

  Future<void> _previewMenu() async {
    final picked = await showV13ActionSheet<String>(
      context,
      title: 'Crew',
      actions: const [
        V13SheetAction(
          label: 'Report crew',
          value: 'report',
          icon: Icons.flag_outlined,
          destructive: true,
        ),
      ],
    );
    if (picked == 'report' && mounted) _report();
  }

  Future<void> _shareCrew(CrewGroup g) async {
    final text =
        'Join my crew "${g.name}" on Nuvo. Crew code: ${g.joinCode}'
        '\nhttps://getnuvo.net/c/${g.joinCode}';
    Rect? origin;
    try {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.width > 0 && rect.height > 0) origin = rect;
      }
    } catch (_) {
      origin = null;
    }
    var copied = false;
    try {
      final result = await Share.share(
        text,
        subject: g.name,
        sharePositionOrigin: origin,
      );
      copied = result.status == ShareResultStatus.unavailable;
    } catch (_) {
      copied = true;
    }
    if (!copied || !mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showV13Toast(context, 'Invite copied — paste it into a message');
    }
  }

  Future<void> _copyInvite(CrewGroup g) async {
    await Clipboard.setData(
      ClipboardData(text: 'https://getnuvo.net/c/${g.joinCode}'),
    );
    if (mounted) showV13Toast(context, 'Invite link copied.');
  }

  Future<void> _toggleMute(CrewGroup g, bool muted) async {
    final next = !muted;
    setState(() => _muted = next);
    try {
      await ref.read(squadRepositoryProvider).setMuted(widget.crewId, on: next);
      if (mounted) {
        showV13Toast(context, next ? 'Crew muted.' : 'Crew unmuted.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _muted = muted);
      showV13Toast(context, "Couldn't update. Try again.");
    }
  }

  Future<void> _leave(CrewGroup g) async {
    final ok = await showV13ConfirmSheet(
      context,
      title: 'Leave ${g.name}?',
      body: 'You can rejoin with the crew code.',
      confirmLabel: 'Leave crew',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(squadControllerProvider.notifier).leave(widget.crewId);
      if (!mounted) return;
      showV13Toast(context, 'You left ${g.name}.');
      context.go('/pass');
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't leave. Try again.");
    }
  }

  Future<void> _report() async {
    final ok = await showV13ConfirmSheet(
      context,
      title: 'Report this crew?',
      body: 'Our team reviews every report.',
      confirmLabel: 'Report crew',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(squadRepositoryProvider).reportCrew(widget.crewId);
      if (mounted) {
        showV13Toast(context, 'Thanks — we got your report.');
      }
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't send the report. Try again.");
      }
    }
  }

  Future<void> _showJoinRequests() async {
    await showV13Sheet<void>(
      context,
      builder: (_) => _JoinRequestsSheet(crewId: widget.crewId),
    );
    if (mounted) {
      ref.read(squadControllerProvider.notifier).refreshDetail(widget.crewId);
    }
  }

  Future<void> _manageMember(CrewGroup g, CrewMember member) async {
    final myId = ref.read(authControllerProvider).user?.id;
    if (member.userId == myId) return;
    final iAmOwner = g.isOwner || g.myRole == 'owner';
    final canRemove =
        !member.isOwner && (iAmOwner || (!member.isAdmin && g.canManage));
    final canRole = iAmOwner && !member.isOwner;
    if (!canRemove && !canRole) return;
    final picked = await showV13ActionSheet<String>(
      context,
      title: member.displayName,
      actions: [
        if (canRole)
          V13SheetAction(
            label: member.isAdmin ? 'Remove admin' : 'Make admin',
            value: 'role',
            icon: Icons.shield_outlined,
          ),
        if (canRemove)
          const V13SheetAction(
            label: 'Remove from crew',
            value: 'remove',
            icon: Icons.person_remove_outlined,
            destructive: true,
          ),
      ],
    );
    if (!mounted || picked == null) return;
    final controller = ref.read(squadControllerProvider.notifier);
    try {
      if (picked == 'role') {
        final role = member.isAdmin ? 'member' : 'admin';
        await controller.setRole(widget.crewId, member.userId, role);
        if (mounted) {
          showV13Toast(
            context,
            role == 'admin'
                ? '${member.displayName.split(' ').first} is an admin now.'
                : '${member.displayName.split(' ').first} is a member now.',
          );
        }
      } else if (picked == 'remove') {
        final ok = await showV13ConfirmSheet(
          context,
          title: 'Remove ${member.displayName.split(' ').first}?',
          body: 'They can rejoin with the crew code.',
          confirmLabel: 'Remove',
          destructive: true,
        );
        if (ok != true || !mounted) return;
        await controller.removeMember(widget.crewId, member.userId);
        if (mounted) showV13Toast(context, 'Member removed.');
      }
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't update. Try again.");
    }
  }

  Future<void> _toggleAutoJoin(CrewRecurringRace recurring, bool on) async {
    if (_autoJoinBusy.contains(recurring.id)) return;
    setState(() {
      _autoJoin[recurring.id] = on;
      _autoJoinBusy.add(recurring.id);
    });
    try {
      await ref
          .read(squadRepositoryProvider)
          .setRecurringAutoJoin(widget.crewId, recurring.id, on: on);
    } catch (_) {
      if (!mounted) return;
      setState(() => _autoJoin.remove(recurring.id));
      showV13Toast(context, "Couldn't update auto-join. Try again.");
    } finally {
      if (mounted) setState(() => _autoJoinBusy.remove(recurring.id));
    }
  }

  Future<void> _askToJoin() async {
    setState(() => _joinBusy = true);
    try {
      await ref.read(squadRepositoryProvider).joinRequest(widget.crewId);
      if (!mounted) return;
      setState(() {
        _joinBusy = false;
        _requested = true;
      });
      showV13Toast(context, 'Request sent.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _joinBusy = false);
      showV13Toast(context, "Couldn't send the request. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(squadControllerProvider);
    final detail = state.details[widget.crewId];
    final loading = state.detailLoading.contains(widget.crewId);
    final error = state.detailErrors[widget.crewId];

    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: detail != null
            ? _memberPage(detail)
            : loading
            ? _loadingView()
            : error != null
            ? _previewOrError()
            : _loadingView(),
      ),
    );
  }

  Widget _loadingView() => const Column(
    children: [
      V13BackBar(title: 'Crew', fallback: '/pass'),
      Padding(
        padding: EdgeInsets.all(V13.pagePad),
        child: V13Skeleton.screen(),
      ),
    ],
  );

  Widget _previewOrError() {
    final previewAsync = ref.watch(crewPreviewProvider(widget.crewId));
    if (previewAsync.isLoading && !previewAsync.hasValue) {
      return _loadingView();
    }
    final preview = previewAsync.valueOrNull;
    if (preview == null) {
      return Column(
        children: [
          const V13BackBar(title: 'Crew', fallback: '/pass'),
          Expanded(
            child: V13AsyncView<Never>.state(
              status: V13AsyncStatus.error,
              errorTitle: "Couldn't load this crew",
              errorBody: 'It may have been removed — or try again.',
              onRetry: () {
                ref.invalidate(crewPreviewProvider(widget.crewId));
                _refresh();
              },
              builder: (_) => const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    return _previewPage(preview);
  }

  Widget _previewPage(CrewGroupPreview preview) {
    final requested = _requested || preview.requested;
    return Column(
      children: [
        V13BackBar(
          title: 'Crew',
          fallback: '/pass',
          trailing: [
            V13IconButton(
              icon: Icons.more_horiz,
              semanticLabel: 'Crew actions',
              onTap: _previewMenu,
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            children: [
              V13IconTile(
                icon: Icons.groups,
                color: V13.crewColor(preview.colorKey, preview.id),
                size: 76,
                radius: V13.radiusTileLg,
              ),
              const SizedBox(height: V13.gapMd),
              Text(preview.name, style: V13.title),
              const SizedBox(height: 4),
              Text(
                [
                  '${preview.memberCount} '
                      'member${preview.memberCount == 1 ? '' : 's'}',
                  if (preview.ownerName != null) 'Run by ${preview.ownerName}',
                ].join(' · '),
                style: V13.caption,
              ),
              if (preview.bio != null && preview.bio!.trim().isNotEmpty) ...[
                const SizedBox(height: V13.gapSm),
                Text(preview.bio!.trim(), style: V13.body),
              ],
              if (preview.memberPreviews.isNotEmpty) ...[
                const SizedBox(height: V13.gapMd),
                V13FaceStack(
                  faces: [
                    for (final m in preview.memberPreviews.take(5))
                      V13FaceInfo(
                        id: m.userId,
                        photoUrl: m.profilePhotoUrl,
                        name: m.displayName,
                      ),
                  ],
                  total: preview.memberCount,
                  size: 32,
                ),
              ],
              const SizedBox(height: V13.gapXl),
              if (preview.isMember)
                const V13Pill(label: "You're in this crew", color: V13.mint)
              else if (requested)
                const V13Pill(label: 'Requested', color: V13.lilac)
              else
                V13Button.primary(
                  label: 'Ask to join',
                  fullWidth: true,
                  loading: _joinBusy,
                  onPressed: _askToJoin,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberPage(CrewGroupDetail detail) {
    final g = detail.group;
    final myId = ref.watch(authControllerProvider).user?.id;
    final crewColor = V13.crewColor(g.colorKey, g.id);
    final weekAsync = ref.watch(crewWeekStandingsProvider(widget.crewId));
    // The switch hides once the endpoint is known-missing (W2 not merged).
    final weekSupported = weekAsync.hasValue
        ? weekAsync.valueOrNull != null
        : true;
    final showingWeek = weekSupported && _period == 0;

    final stats = [
      if (g.stats?.wins != null)
        V13Stat(label: 'Crew wins', value: '${g.stats!.wins}'),
      V13Stat(label: 'Races', value: '${g.stats?.races ?? g.raceCount}'),
      if (g.stats?.streakDays != null)
        V13Stat(label: 'Crew streak', value: '${g.stats!.streakDays}'),
    ];

    final members = [...detail.members]
      ..sort((a, b) {
        int rank(String role) => role == 'owner'
            ? 0
            : role == 'admin'
            ? 1
            : 2;
        final byRole = rank(a.role).compareTo(rank(b.role));
        return byRole != 0 ? byRole : a.displayName.compareTo(b.displayName);
      });

    return RefreshIndicator(
      color: V13.blue,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: V13TabBar.bottomPadding(context)),
        children: [
          V13BackBar(
            title: g.name,
            fallback: '/pass',
            trailing: [
              V13IconButton(
                icon: Icons.more_horiz,
                semanticLabel: 'Crew actions',
                onTap: () => _menu(detail),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: CrewPageHeader(crew: g),
          ),
          const SizedBox(height: V13.gapXl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: Row(
              children: [
                Expanded(
                  child: V13Button.primary(
                    label: 'Start a crew race',
                    icon: Icons.flag,
                    onPressed: () => _startRace(detail),
                  ),
                ),
                const SizedBox(width: V13.gapMd),
                V13Button.secondary(
                  label: 'Invite',
                  icon: Icons.qr_code_2,
                  onPressed: () => context.push('/my-nuvo'),
                ),
              ],
            ),
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: V13.gapXxl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: V13StatTriple(stats: stats),
            ),
          ],
          const SizedBox(height: V13.gapSection),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: V13SectionHeader(title: 'Leaderboard'),
          ),
          if (weekSupported) ...[
            const SizedBox(height: V13.gapMd),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: V13Segmented(
                segments: const [
                  V13Segment(label: 'This week'),
                  V13Segment(label: 'All time'),
                ],
                selectedIndex: _period,
                onChanged: (i) => setState(() => _period = i),
                semanticLabel: 'Leaderboard period',
              ),
            ),
          ],
          const SizedBox(height: V13.gapSm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: _standings(detail, weekAsync, showingWeek),
          ),
          if (detail.recurring.isNotEmpty) ...[
            const SizedBox(height: V13.gapSection),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: V13SectionHeader(
                title: 'Recurring races',
                trailingLabel: g.canManage ? '+ Add' : null,
                onTrailingTap: g.canManage ? () => _startRace(detail) : null,
              ),
            ),
            const SizedBox(height: V13.gapMd),
            for (final recurring in detail.recurring) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
                child: RecurringRaceCard(
                  recurring: recurring,
                  crewColor: crewColor,
                  autoJoin:
                      _autoJoin[recurring.id] ?? recurring.autoJoin ?? true,
                  busy: _autoJoinBusy.contains(recurring.id),
                  onToggle: (on) => _toggleAutoJoin(recurring, on),
                ),
              ),
              const SizedBox(height: V13.gapMd),
            ],
          ],
          if (detail.battle != null && detail.battle!.isActive) ...[
            const SizedBox(height: V13.gapSection),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: V13SectionHeader(title: 'Crew battle'),
            ),
            const SizedBox(height: V13.gapMd),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: CrewBattleCard(
                battle: detail.battle!,
                crewName: g.name,
                crewColor: crewColor,
              ),
            ),
          ],
          const SizedBox(height: V13.gapSection),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: V13SectionHeader(title: 'Members · ${members.length}'),
          ),
          const SizedBox(height: V13.gapMd),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
            child: Wrap(
              spacing: V13.gapMd,
              runSpacing: V13.gapLg,
              children: [
                for (final member in members)
                  MemberCell(
                    member: member,
                    isMe: member.userId == myId,
                    onTap: () => openPerson(context, ref, member.userId),
                    onLongPress: g.canManage
                        ? () => _manageMember(g, member)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _standings(
    CrewGroupDetail detail,
    AsyncValue<List<CrewGroupStanding>?> weekAsync,
    bool showingWeek,
  ) {
    if (showingWeek) {
      if (weekAsync.isLoading && !weekAsync.hasValue) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: V13.gapMd),
          child: V13Skeleton.box(width: double.infinity, height: 140),
        );
      }
      if (weekAsync.hasError && !weekAsync.hasValue) {
        return CrewSectionError(
          message: "Couldn't load this week",
          onRetry: () =>
              ref.invalidate(crewWeekStandingsProvider(widget.crewId)),
        );
      }
      final rows = weekAsync.valueOrNull ?? detail.standings;
      if (rows.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
          child: Text(
            'No points this week — a race win counts here.',
            style: V13.caption,
          ),
        );
      }
      return _standingRows(detail, rows);
    }
    final rows = detail.standings;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
        child: Text(
          'No points yet — a race win counts here.',
          style: V13.caption,
        ),
      );
    }
    return _standingRows(detail, rows);
  }

  Widget _standingRows(CrewGroupDetail detail, List<CrewGroupStanding> rows) {
    final roleByUser = {for (final m in detail.members) m.userId: m.role};
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const V13Divider(),
          StandingRow(
            standing: rows[i],
            role: roleByUser[rows[i].userId],
            onTap: () => openPerson(context, ref, rows[i].userId),
          ),
        ],
      ],
    );
  }
}

/// The join-requests sheet — owner/admin approves or declines each ask.
class _JoinRequestsSheet extends ConsumerStatefulWidget {
  const _JoinRequestsSheet({required this.crewId});

  final String crewId;

  @override
  ConsumerState<_JoinRequestsSheet> createState() => _JoinRequestsSheetState();
}

class _JoinRequestsSheetState extends ConsumerState<_JoinRequestsSheet> {
  List<CrewMemberPreview>? _requests;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _requests = ref
        .read(squadControllerProvider)
        .details[widget.crewId]
        ?.joinRequests;
  }

  Future<void> _act(CrewMemberPreview request, bool approve) async {
    setState(() => _busy.add(request.userId));
    final repo = ref.read(squadRepositoryProvider);
    try {
      if (approve) {
        await repo.approveJoinRequest(widget.crewId, request.userId);
      } else {
        await repo.declineJoinRequest(widget.crewId, request.userId);
      }
      if (!mounted) return;
      setState(() {
        _busy.remove(request.userId);
        _requests = [
          for (final r in _requests ?? const [])
            if (r.userId != request.userId) r,
        ];
      });
      if (approve) showV13Toast(context, '${request.displayName} is in.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy.remove(request.userId));
      showV13Toast(context, "Couldn't update. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = _requests ?? const <CrewMemberPreview>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Join requests', style: V13.sectionHead),
          const SizedBox(height: V13.gapMd),
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: V13.gapLg),
              child: Text('No requests waiting.', style: V13.caption),
            )
          else
            for (final request in requests)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: V13.gapSm),
                child: Row(
                  children: [
                    V13Face(
                      photoUrl: request.profilePhotoUrl,
                      size: 40,
                      name: request.displayName,
                    ),
                    const SizedBox(width: V13.gapMd),
                    Expanded(
                      child: Text(
                        request.displayName,
                        style: V13.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    V13Button.ghost(
                      label: 'Decline',
                      size: V13ButtonSize.small,
                      onPressed: _busy.contains(request.userId)
                          ? null
                          : () => _act(request, false),
                    ),
                    const SizedBox(width: V13.gapSm),
                    V13Button.primary(
                      label: 'Approve',
                      size: V13ButtonSize.small,
                      loading: _busy.contains(request.userId),
                      onPressed: _busy.contains(request.userId)
                          ? null
                          : () => _act(request, true),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
