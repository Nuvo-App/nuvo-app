import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_fade_scroll.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../../core/widgets/nuvo_stagger_in.dart';
import '../../crew/application/crew_controller.dart';
import '../../races/data/race_models.dart';
import '../../social/domain/nuvo_destination.dart';
import '../../social/domain/social_event_accent.dart';
import '../application/notification_controller.dart';
import '../data/notification_models.dart';
import '../domain/notification_display.dart';

/// `/notifications` — the inbox. Fully useful without push: the backend
/// notification record is canonical (docs/agents/19 §9). Follows the freshness
/// contract; a tap marks read + deep-links via the structured destination.
///
/// Rows use the shared social color grammar (social_event_accent.dart) — a
/// small saturated accent marks what happened; read/unread is a text-weight +
/// dot signal, not a background flood.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _State();
}

class _State extends ConsumerState<NotificationsScreen> {
  final _scroll = ScrollController();
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(notificationControllerProvider.notifier).loadMore();
      }
    });
    // Cold open — load if we have nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationControllerProvider.notifier).load(force: false);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _open(NuvoNotification n) {
    ref.read(notificationControllerProvider.notifier).markRead(n.id);
    final dest = n.destination;
    if (dest != null) context.push(dest.location);
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
      if (mounted) {
        ref.read(notificationControllerProvider.notifier).markRead(n.id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That didn't go through. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationControllerProvider);
    final t = context.themeColors;
    return NuvoPage(
      topBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
          child: Row(
            children: [
              NuvoBackButton(
                onPressed: () => context.canPop() ? context.pop() : context.go('/arena'),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Notifications', style: AppTextStyles.headlineMedium),
                  if (state.unreadCount > 0)
                    Text(
                      '${state.unreadCount} unread',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: t.inkSubtle),
                    ),
                ],
              ),
              const Spacer(),
              if (state.unreadCount > 0)
                IconButton(
                  onPressed: () =>
                      ref.read(notificationControllerProvider.notifier).markAllRead(),
                  icon: const Icon(Icons.done_all_rounded),
                  color: t.ink,
                  tooltip: 'Mark all read',
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                onPressed: () => context.push('/settings/notifications'),
                icon: const Icon(Icons.tune_rounded),
                color: t.inkSubtle,
                tooltip: 'Notification settings',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
      child: _body(state),
    );
  }

  Widget _body(NotificationState state) {
    if (state.loading && !state.hasData) {
      return const Center(child: NuvoLoadingIndicator());
    }
    if (!state.hasData && state.error != null) {
      return Center(
        child: NuvoErrorState(
          message: state.error!,
          onRetry: () =>
              ref.read(notificationControllerProvider.notifier).load(force: true),
        ),
      );
    }
    if (!state.hasData) {
      return const Center(
        child: NuvoEmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'You’re all caught up',
          body: 'Race invites, crew requests and results will show up here.',
          align: TextAlign.center,
        ),
      );
    }
    final t = context.themeColors;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(notificationControllerProvider.notifier).load(force: true),
      child: NuvoFadeScroll(
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // One grouped surface, hairline separators — the stack reads as a
            // single ledger instead of floating cards competing for attention.
            Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.border, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < state.items.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: t.divider),
                    NuvoStaggerIn(
                      index: i,
                      child: _NotificationRow(
                        item: state.items[i],
                        busy: _busy.contains(state.items[i].id),
                        onTap: () => _open(state.items[i]),
                        onAccept: () =>
                            _resolveCrew(state.items[i], true),
                        onDecline: () =>
                            _resolveCrew(state.items[i], false),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (state.hasMore)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: NuvoLoadingIndicator(size: 20)),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.onTap,
    required this.onAccept,
    required this.onDecline,
    required this.busy,
  });

  final NuvoNotification item;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool busy;

  /// A pending crew request stays actionable until the viewer answers it —
  /// those rows get inline Accept/Decline instead of routing away.
  bool get _isActionableRequest {
    return item.category == 'crew_request' &&
        !item.read &&
        item.destination is ProfileDestination;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeColors;
    final accent = socialAccentFor(item.category);
    final role = accent.role(context);
    final icon = socialAccentIcon(item.category);
    return NuvoPressable(
      onTap: onTap,
      haptic: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        // Unread = a quiet ice wash; the event color lives in the marker.
        color: item.read ? t.surface : t.panelLight,
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The saturated event marker — the only place category color
            // floods, so a long inbox stays scannable by color alone.
            Container(
              width: 4,
              height: 44,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: accent == SocialAccent.neutral
                    ? t.divider
                    : role.base,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                NuvoAvatar(
                  initials: notificationInitials(item.actorName),
                  photoUrl: item.actorPhotoUrl,
                  size: 38,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: accent == SocialAccent.neutral
                          ? t.inkMuted
                          : role.base,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: item.read ? t.surface : t.panelLight,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(icon, size: 10, color: NuvoColors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: t.ink,
                            fontWeight:
                                item.read ? FontWeight.w500 : FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        notificationRelativeTime(item.createdAt),
                        style: AppTextStyles.labelSmall
                            .copyWith(color: t.inkSubtle),
                      ),
                    ],
                  ),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: t.inkSubtle),
                    ),
                  ],
                  if (_isActionableRequest) ...[
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        NuvoOutlineButton(
                          label: 'Decline',
                          small: true,
                          height: 36,
                          onPressed: busy ? null : onDecline,
                        ),
                        const SizedBox(width: 8),
                        NuvoPrimaryButton(
                          label: 'Accept',
                          small: true,
                          height: 36,
                          loading: busy,
                          onPressed: busy ? null : onAccept,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!item.read)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 3),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: role.base,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
