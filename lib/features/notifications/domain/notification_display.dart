/// Shared display formatting for notification-shaped rows (the notifications
/// inbox and the Crew activity feed both render actor initials + relative
/// time from a `NuvoNotification` / `PublicUser`-adjacent shape).
library;

import 'package:intl/intl.dart';

String notificationInitials(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return 'N';
  final parts = trimmed.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return parts.first[0].toUpperCase();
}

String notificationRelativeTime(DateTime createdAtUtc) {
  final age = DateTime.now().toUtc().difference(createdAtUtc);
  if (age.isNegative || age < const Duration(minutes: 1)) return 'Just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes}m ago';
  if (age < const Duration(days: 1)) return '${age.inHours}h ago';
  if (age < const Duration(days: 7)) return '${age.inDays}d ago';
  return DateFormat.MMMd().format(createdAtUtc.toLocal());
}
