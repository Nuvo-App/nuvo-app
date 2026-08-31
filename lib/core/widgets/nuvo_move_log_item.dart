import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';

class NuvoMoveLogItem extends StatelessWidget {
  const NuvoMoveLogItem({
    super.key,
    required this.displayName,
    required this.actionLine,
    required this.createdAt,
    this.profilePhotoUrl,
    this.valueLabel,
    this.isPositive = true,
    this.onTap,
  });

  final String displayName;
  final String actionLine; // e.g. "logged 20 pushups · Move checked"
  final String createdAt; // ISO string
  final String? profilePhotoUrl;
  final String? valueLabel; // e.g. "+20 reps"
  final bool isPositive;
  final VoidCallback? onTap;

  static String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  String get _initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = displayName.trim();
    return s.isEmpty ? '?' : s[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel = _timeAgo(createdAt);

    // Flat row — the containing list provides the single surface. No border,
    // no shadow, no margin: shadows mean "tappable surface", and a log entry
    // is content.
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            NuvoAvatar(
              initials: _initials,
              photoUrl: profilePhotoUrl,
              size: 36,
              borderColor: NuvoColors.navy,
              borderWidth: 1.5,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: AppTextStyles.titleMedium.copyWith(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$actionLine${timeLabel.isNotEmpty ? ' · $timeLabel' : ''}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (valueLabel != null) ...[
              const SizedBox(width: 10),
              Text(
                valueLabel!,
                style: AppTextStyles.labelSmall.copyWith(
                  color: isPositive ? NuvoColors.successOn : NuvoColors.dangerOn,
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
