import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.inkNavy, width: 2),
          boxShadow: AppShadows.hardShadow3,
        ),
        child: Row(
          children: [
            NuvoAvatar(
              initials: _initials,
              photoUrl: profilePhotoUrl,
              size: NuvoAvatarSizes.lg,
              borderColor: NuvoColors.white,
              borderWidth: 2,
            ),
            const SizedBox(width: 14),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPositive
                      ? NuvoColors.success.withValues(alpha: 0.10)
                      : NuvoColors.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  valueLabel!,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isPositive ? NuvoColors.success : NuvoColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
