import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../application/notification_controller.dart';

/// The app-bar bell with an unread badge. Tapping it opens `/notifications`
/// and revalidates the inbox.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final tint = color ?? NuvoColors.navy;
    return Semantics(
      button: true,
      label: unread > 0 ? '$unread unread notifications' : 'Notifications',
      child: GestureDetector(
        onTap: () {
          ref.read(notificationControllerProvider.notifier).markStale();
          context.push('/notifications');
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.notifications_none_rounded, color: tint, size: 24),
              if (unread > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: NuvoColors.danger,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: NuvoColors.page, width: 1.5),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1.4,
                      ),
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
