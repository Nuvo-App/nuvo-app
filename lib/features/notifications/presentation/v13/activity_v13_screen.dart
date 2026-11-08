import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/v13/v13.dart';
import '../../../crew/application/crew_controller.dart';
import '../../../races/data/race_models.dart';
import '../../../races/presentation/race_controller.dart';
import '../../../races/presentation/v13/submit_proof_entry.dart';
import '../../../social/domain/nuvo_destination.dart';
import '../../application/notification_controller.dart';
import '../../data/notification_models.dart';
import '../../domain/notification_display.dart';

/// The v13 Activity inbox — `GET /notifications` grouped into New (what was
/// unread when the screen opened) and Earlier. Each row carries the actor's
/// face, the copy, relative time and one inline action where it fits:
///
///  * `passed_on_leaderboard` / `proof_rejected` → **Take it back** opens
///    Submit proof for that race (`openSubmitProof`, falling back to
///    `/race/:id/proof` when the race can't be loaded).
///  * `crew_request` (still pending) → **Accept / Decline** through the
///    existing crew request flow.
///  * `race_invite` → **Accept** joins the race through the existing join
///    flow, then lands on the race.
///  * everything else with a destination → **View**.
///
/// Opening the screen calls `markAllRead()` (POST /notifications/read-all)
/// so the bell badge clears; New/Earlier grouping keys off the snapshot
/// taken before that call, per the mapping doc.
class ActivityV13Screen extends ConsumerStatefulWidget {
  const ActivityV13Screen({super.key});

  @override
  ConsumerState<ActivityV13Screen> createState() => _ActivityV13ScreenState();
}

class _ActivityV13ScreenState extends ConsumerState<ActivityV13Screen> {
  final ScrollController _scroll = ScrollController();

  /// Ids unread when the inbox first landed — the "New" group. Survives
  /// the optimistic mark-all patch; newly arriving unread items join it.
  final Set<String> _newIds = {};

  /// Ids the viewer explicitly handled this session (tapped through or
  /// resolved inline) — kills actionability even if a refresh re-delivers
  /// the row unread.
  final Set<String> _handled = {};

  final Set<String> _busy = {};
  bool _markAllFired = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    final openedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(analyticsProvider).screen(
        'activity',
        ms: DateTime.now().difference(openedAt).inMilliseconds,
      );
      ref.read(notificationControllerProvider.notifier).load(force: false);
      // If the inbox is already populated (re-open, warm cache), the state
      // listener below never fires for the current value — seed from it.
      _seed(ref.read(notificationControllerProvider));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    final state = ref.read(notificationControllerProvider);
    if (!state.hasMore || state.loadingMore) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 400) {
      ref.read(notificationControllerProvider.notifier).loadMore();
    }
  }

  /// Snapshot unread ids into the New group and fire the read-all POST once
  /// data lands. Runs on every emission so arrivals mid-session also join.
  void _seed(NotificationState next) {
    for (final n in next.items) {
      if (!n.read) _newIds.add(n.id);
    }
    if (!_markAllFired && next.hasData) {
      _markAllFired = true;
      ref.read(notificationControllerProvider.notifier).markAllRead();
    }
  }

  void _onState(NotificationState? prev, NotificationState next) {
    _seed(next);
    if (mounted) setState(() {});
  }

  void _open(NuvoNotification n) {
    _handled.add(n.id);
    ref.read(notificationControllerProvider.notifier).markRead(n.id);
    final dest = n.destination;
    if (dest != null) context.push(dest.location);
  }

  void _openActor(NuvoNotification n) {
    final id = n.actorId;
    if (id != null && id.isNotEmpty) {
      openPerson(context, ref, id);
    }
  }

  Future<void> _resolveCrew(NuvoNotification n, bool accept) async {
    final dest = n.destination;
    if (dest is! ProfileDestination) return;
    final name = n.actorName ?? 'Nuvo member';
    final user = PublicUser(
      id: dest.userId,
      displayName: name,
      initials: notificationInitials(name),
      profilePhotoUrl: n.actorPhotoUrl,
    );
    setState(() => _busy.add(n.id));
    final crew = ref.read(crewControllerProvider.notifier);
    try {
      if (accept) {
        await crew.acceptRequest(user);
      } else {
        await crew.declineRequest(user);
      }
      // The crew controller's onRequestResolved marks the notification read;
      // do it locally too so the action row collapses even if that hook is
      // absent (e.g. a detached provider in tests).
      _handled.add(n.id);
      if (mounted) {
        ref.read(notificationControllerProvider.notifier).markRead(n.id);
      }
      if (accept && mounted) showV13Confetti(context);
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "That didn't go through. Try again.");
      }
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  /// `Take it back` — Submit proof on the race that passed you (or rejected
  /// your proof). Prefers the v13 sheet via a resolved [Race]; falls back
  /// to the proof route when the race can't be loaded.
  Future<void> _takeItBack(NuvoNotification n) async {
    final dest = n.destination;
    if (dest is! RaceDestination) return;
    _handled.add(n.id);
    ref.read(notificationControllerProvider.notifier).markRead(n.id);
    setState(() => _busy.add(n.id));
    try {
      final races = ref.read(raceControllerProvider).races;
      final race =
          races.where((r) => r.id == dest.raceId).firstOrNull ??
          await ref
              .read(raceControllerProvider.notifier)
              .getRaceDetail(dest.raceId);
      if (!mounted) return;
      await openSubmitProof(context, ref, race);
    } catch (_) {
      if (mounted) context.push('/race/${dest.raceId}/proof');
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  /// `Accept` on a race invite — join through the existing join flow, then
  /// land on the race.
  Future<void> _acceptInvite(NuvoNotification n) async {
    final dest = n.destination;
    if (dest is! RaceDestination) return;
    setState(() => _busy.add(n.id));
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .joinRace(dest.raceId);
      _handled.add(n.id);
      if (!mounted) return;
      ref.read(notificationControllerProvider.notifier).markRead(n.id);
      showV13Confetti(context);
      context.push('/race/${race.id}');
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't join the race. Try again.");
      }
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  bool _isPendingRequest(NuvoNotification n) =>
      n.category == 'crew_request' &&
      n.destination is ProfileDestination &&
      !_handled.contains(n.id) &&
      (_newIds.contains(n.id) || !n.read);

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationControllerProvider, _onState);
    final state = ref.watch(notificationControllerProvider);

    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: 'Activity',
              fallback: '/arena',
              trailing: [
                V13IconButton(
                  icon: Icons.tune_rounded,
                  shape: V13IconButtonShape.square,
                  semanticLabel: 'Notification settings',
                  onTap: () => context.push('/settings/notifications'),
                ),
              ],
            ),
            Expanded(child: _body(state)),
          ],
        ),
      ),
    );
  }

  Widget _body(NotificationState state) {
    final status = state.loading && !state.hasData
        ? V13AsyncStatus.loading
        : state.error != null && !state.hasData
        ? V13AsyncStatus.error
        : !state.hasData
        ? V13AsyncStatus.empty
        : V13AsyncStatus.data;
    return V13AsyncView<NotificationState>.state(
      status: status,
      dataValue: state,
      emptyIcon: Icons.notifications_none_rounded,
      emptyTitle: 'You’re all caught up',
      emptyBody: 'Race invites, friend requests and results will show up here.',
      errorTitle: "Couldn't load activity",
      errorBody: state.error ?? 'Check your connection and try again.',
      onRetry: () =>
          ref.read(notificationControllerProvider.notifier).load(force: true),
      onRefresh: () =>
          ref.read(notificationControllerProvider.notifier).load(force: true),
      loadingWidget: const _ActivitySkeleton(),
      builder: (s) => _list(s),
    );
  }

  /// Activity-style sections: New (unread when opened), then Today /
  /// This week / Earlier by date.
  static String _bucket(DateTime createdUtc) {
    final now = DateTime.now();
    final local = createdUtc.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    if (!local.isBefore(today)) return 'Today';
    if (!local.isBefore(DateTime(now.year, now.month, now.day - 6))) {
      return 'This week';
    }
    return 'Earlier';
  }

  /// Rows that ask for a decision stay single; everything else collapses
  /// with its neighbours when it's the same kind of event about the same
  /// thing ("Sunil and 2 others reacted…").
  bool _groupable(NuvoNotification n) =>
      !_isPendingRequest(n) && n.category != 'race_invite';

  String _groupKey(NuvoNotification n) =>
      '${n.category}|${n.destination?.location ?? n.title}';

  List<List<NuvoNotification>> _grouped(List<NuvoNotification> items) {
    final out = <List<NuvoNotification>>[];
    final byKey = <String, List<NuvoNotification>>{};
    for (final n in items) {
      if (!_groupable(n)) {
        out.add([n]);
        continue;
      }
      final k = _groupKey(n);
      final existing = byKey[k];
      if (existing != null &&
          existing.every((e) => e.actorId != n.actorId || n.actorId == null)) {
        existing.add(n);
      } else if (existing == null) {
        final g = [n];
        byKey[k] = g;
        out.add(g);
      } else {
        out.add([n]);
      }
    }
    return out;
  }

  Widget _list(NotificationState state) {
    final sections = <String, List<NuvoNotification>>{
      'New': [],
      'Today': [],
      'This week': [],
      'Earlier': [],
    };
    for (final n in state.items) {
      final key = _newIds.contains(n.id) ? 'New' : _bucket(n.createdAt);
      sections[key]!.add(n);
    }
    var index = 0;
    final children = <Widget>[
      for (final entry in sections.entries)
        if (entry.value.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: V13.gapLg, bottom: 2),
            child: V13SectionHeader(title: entry.key),
          ),
          for (final g in _grouped(entry.value))
            V13StaggerIn(
              key: ValueKey('act-${g.first.id}'),
              index: index++,
              child: _row(g.first, others: g.skip(1).toList()),
            ),
        ],
      if (state.loadingMore || state.hasMore)
        Padding(
          padding: const EdgeInsets.all(V13.gapLg),
          child: Center(
            child: state.loadingMore
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: V13.blue,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
    ];
    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        V13.pagePad,
        0,
        V13.pagePad,
        MediaQuery.paddingOf(context).bottom + 32,
      ),
      children: children,
    );
  }

  Widget _row(NuvoNotification n, {List<NuvoNotification> others = const []}) {
    final busy = _busy.contains(n.id);
    final pendingRequest = _isPendingRequest(n);
    final showUnreadDot = _newIds.contains(n.id) && !_handled.contains(n.id);
    return _ActivityRow(
      item: n,
      others: others,
      busy: busy,
      showUnreadDot: showUnreadDot,
      pendingRequest: pendingRequest,
      onTap: () => _open(n),
      onActorTap: () => _openActor(n),
      onTakeItBack: () => _takeItBack(n),
      onAccept: () => _resolveCrew(n, true),
      onDecline: () => _resolveCrew(n, false),
      onAcceptInvite: () => _acceptInvite(n),
      onView: () => _open(n),
    );
  }
}

/// One inbox row — actor face, copy, relative time, inline action. Open
/// rows with the 2px v13 divider, never boxed cards.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.item,
    this.others = const [],
    required this.busy,
    required this.showUnreadDot,
    required this.pendingRequest,
    required this.onTap,
    required this.onActorTap,
    required this.onTakeItBack,
    required this.onAccept,
    required this.onDecline,
    required this.onAcceptInvite,
    required this.onView,
  });

  final NuvoNotification item;

  /// Similar events folded into this row ("and 2 others").
  final List<NuvoNotification> others;
  final bool busy;
  final bool showUnreadDot;

  /// Still-open `crew_request` — renders Accept/Decline instead of routing.
  final bool pendingRequest;
  final VoidCallback onTap;
  final VoidCallback onActorTap;
  final VoidCallback onTakeItBack;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onAcceptInvite;
  final VoidCallback onView;

  Widget? _action() {
    if (pendingRequest) {
      return Row(
        children: [
          V13Button.secondary(
            label: 'Decline',
            size: V13ButtonSize.small,
            onPressed: busy ? null : onDecline,
          ),
          const SizedBox(width: V13.gapSm),
          V13Button.primary(
            label: 'Accept',
            size: V13ButtonSize.small,
            loading: busy,
            onPressed: busy ? null : onAccept,
          ),
        ],
      );
    }
    final dest = item.destination;
    switch (item.category) {
      case 'passed_on_leaderboard':
      case 'proof_rejected':
        if (dest is! RaceDestination) return null;
        return V13Button.primary(
          label: 'Take it back',
          size: V13ButtonSize.small,
          loading: busy,
          onPressed: busy ? null : onTakeItBack,
        );
      case 'race_invite':
        if (dest is! RaceDestination) return null;
        return V13Button.primary(
          label: 'Accept',
          size: V13ButtonSize.small,
          loading: busy,
          onPressed: busy ? null : onAcceptInvite,
        );
      default:
        // The whole row opens its destination — no per-row "View" button.
        return null;
    }
  }

  /// "Sunil passed you" + 2 similar → "Sunil and 2 others passed you".
  String _groupedTitle(String raw) {
    if (others.isEmpty) return raw;
    final actor = item.actorName?.trim().split(RegExp(r'\s+')).first;
    final more = '${others.length} ${others.length == 1 ? 'other' : 'others'}';
    if (actor != null && actor.isNotEmpty && raw.startsWith(actor)) {
      final full = item.actorName!.trim();
      final rest = raw.startsWith(full)
          ? raw.substring(full.length)
          : raw.substring(actor.length);
      return '$actor and $more$rest';
    }
    return '$raw (+$more)';
  }

  @override
  Widget build(BuildContext context) {
    final rawTitle = notificationStripEmoji(item.title);
    final title = _groupedTitle(rawTitle);
    final body = item.body == null ? null : notificationStripEmoji(item.body!);
    final action = _action();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        V13Pressable(
          onTap: onTap,
          pressDepth: 2,
          haptic: false,
          semanticLabel: title,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: V13.gapMd + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (others.isNotEmpty)
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: Stack(
                      children: [
                        V13Face(
                          photoUrl: others.first.actorPhotoUrl,
                          name: others.first.actorName,
                          size: 30,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: V13Face(
                            photoUrl: item.actorPhotoUrl,
                            name: item.actorName,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  V13Face(
                    photoUrl: item.actorPhotoUrl,
                    name: item.actorName,
                    size: 42,
                    // A face opens the actor's profile — only real when the
                    // server sent an actor id.
                    onTap: item.actorId == null || item.actorId!.isEmpty
                        ? null
                        : onActorTap,
                  ),
                const SizedBox(width: V13.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: title,
                              style: showUnreadDot ? V13.bodyStrong : V13.body,
                            ),
                            TextSpan(
                              text:
                                  '  ${notificationRelativeTime(item.createdAt)}',
                              style: V13.caption,
                            ),
                          ],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (body != null &&
                          body.isNotEmpty &&
                          others.isEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: V13.caption,
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: V13.gapSm),
                  action,
                ],
                if (showUnreadDot)
                  Container(
                    margin: const EdgeInsets.only(left: 8, top: 6),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: V13.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const V13Divider(),
      ],
    );
  }
}

/// Loading state — face + two text lines per row, matching the row chrome.
/// A Column, not a ListView: V13AsyncView wraps states in its own scroll
/// for pull-to-refresh, so a nested scrollable would get infinite height.
class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(V13.pagePad, 0, V13.pagePad, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const V13SectionHeader(title: 'New'),
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: V13.gapMd + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  V13Skeleton(height: 42, width: 42, radius: 21),
                  SizedBox(width: V13.gapMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        V13Skeleton(height: 14),
                        SizedBox(height: 6),
                        V13Skeleton(height: 12, width: 160),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
