/// Shared display formatting for notification-shaped rows (the notifications
/// inbox and the Crew activity feed both render actor initials + relative
/// time from a `NuvoNotification` / `PublicUser`-adjacent shape).
library;

import 'package:intl/intl.dart';

String notificationInitials(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return 'N';
  final parts = trimmed
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
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

/// The server decorates some notification copy with emoji (🏁, 👋, …).
/// v13 rows show text + actor face only, so decorative emoji are trimmed
/// at render time — server copy itself is never modified.
final RegExp _notificationEmoji = RegExp(
  '[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
  '\u{FE00}-\u{FE0F}\u{200D}\u{20E3}\u{E0020}-\u{E007F}]',
  unicode: true,
);

String notificationStripEmoji(String text) => text
    .replaceAll(_notificationEmoji, '')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();
