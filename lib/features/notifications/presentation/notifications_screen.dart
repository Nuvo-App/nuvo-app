import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../application/notification_controller.dart';
import '../data/notification_models.dart';

/// `/notifications` — the inbox. Fully useful without push: the backend
/// notification record is canonical (docs/agents/19 §9). Follows the freshness
/// contract; a tap marks read + deep-links via the structured destination.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _State();
}

class _State extends ConsumerState<NotificationsScreen> {
  final _scroll = ScrollController();

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationControllerProvider);
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
              Text('Notifications', style: AppTextStyles.screenTitle),
              const Spacer(),
              if (state.unreadCount > 0)
                TextButton(
                  onPressed: () =>
                      ref.read(notificationControllerProvider.notifier).markAllRead(),
                  child: Text('Mark all read',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: NuvoColors.blue)),
                ),
              IconButton(
                onPressed: () => context.push('/settings/notifications'),
                icon: const Icon(Icons.tune_rounded),
                color: NuvoColors.textMuted,
                tooltip: 'Notification settings',
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
      return const Center(child: CircularProgressIndicator());
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
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(notificationControllerProvider.notifier).load(force: true),
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _NotificationRow(item: state.items[i], onTap: () => _open(state.items[i]));
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item, required this.onTap});

  final NuvoNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: item.read ? NuvoColors.white : NuvoColors.bluePale,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: item.read ? NuvoColors.border : NuvoColors.blueBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NuvoAvatar(
              initials: _initials(item.actorName ?? 'N'),
              photoUrl: item.actorPhotoUrl,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: item.read ? FontWeight.w500 : FontWeight.w700,
                      )),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.body!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: NuvoColors.textMuted)),
                  ],
                  const SizedBox(height: 4),
                  Text(_relative(item.createdAt),
                      style: AppTextStyles.labelSmall
                          .copyWith(color: NuvoColors.textMuted)),
                ],
              ),
            ),
            if (!item.read)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: NuvoColors.blue,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _initials(String n) {
    final p = n.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (p.isEmpty) return 'N';
    if (p.length == 1) return p.first.characters.first.toUpperCase();
    return (p[0].characters.first + p[1].characters.first).toUpperCase();
  }

  static String _relative(DateTime utc) {
    final d = DateTime.now().toUtc().difference(utc);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DateFormat.MMMd().format(utc.toLocal());
  }
}
