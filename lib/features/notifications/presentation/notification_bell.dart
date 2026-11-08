import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/v13/v13.dart';
import '../application/notification_controller.dart';

/// The v13 bell — an outlined icon button with the coral unread badge.
/// Tapping it revalidates the inbox and opens `/notifications`.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return V13IconButton(
      icon: Icons.notifications_none_rounded,
      iconColor: color ?? V13.navy,
      badgeCount: unread > 0 ? unread : null,
      semanticLabel: unread > 0
          ? '$unread unread notifications'
          : 'Notifications',
      onTap: () {
        ref.read(notificationControllerProvider.notifier).markStale();
        context.push('/notifications');
      },
    );
  }
}
