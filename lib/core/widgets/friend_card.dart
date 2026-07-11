import 'package:flutter/material.dart';

import '../../data/models/friend.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'pressable_scale.dart';

class FriendCard extends StatelessWidget {
  const FriendCard({super.key, required this.friend, this.onTap});

  final Friend friend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected = friend.selected;

    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.softBlue : NuvoColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? NuvoColors.blue : NuvoColors.border,
            width: selected ? 1.8 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: NuvoColors.blue.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: selected ? NuvoColors.blue : NuvoColors.navy,
              child: Text(
                friend.initials,
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(friend.name, style: AppTextStyles.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${friend.username} · ${friend.status}',
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? NuvoColors.blue : NuvoColors.icyBlue,
                border: Border.all(
                  color: selected ? NuvoColors.blue : NuvoColors.border,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: NuvoColors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
