import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_card.dart';

/// Data for a crew member / friend entry.
class CrewMember {
  const CrewMember({
    required this.id,
    required this.name,
    required this.username,
    this.activeRaces = 0,
    this.streak = 0,
    this.initial,
  });

  final String id;
  final String name;
  final String username;
  final int activeRaces;
  final int streak;
  final String? initial;

  String get displayInitial =>
      initial ?? (name.isNotEmpty ? name[0].toUpperCase() : '?');
}

/// Crew member row card — avatar, name, stats, Race button.
class FriendCard extends StatelessWidget {
  const FriendCard({
    super.key,
    required this.member,
    this.onRace,
    this.onTap,
    this.selected = false,
    this.selectable = false,
  });

  final CrewMember member;
  final VoidCallback? onRace;
  final VoidCallback? onTap;
  final bool selected;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return NuvoCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onTap,
      borderColor: selected ? NuvoColors.blue : null,
      child: Row(
        children: [
          _Avatar(initial: member.displayInitial, selected: selected),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '@${member.username}',
                  style: AppTextStyles.bodySmall,
                ),
                if (member.activeRaces > 0 || member.streak > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (member.activeRaces > 0) ...[
                        const Icon(Icons.flag_rounded,
                            size: 11, color: NuvoColors.blue),
                        const SizedBox(width: 3),
                        Text(
                          '${member.activeRaces} active',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.blue,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (member.streak > 0) ...[
                        const Icon(Icons.bolt_rounded,
                            size: 11, color: NuvoColors.mint),
                        const SizedBox(width: 3),
                        Text(
                          '${member.streak}d streak',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.mint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (selectable)
            _SelectCircle(selected: selected)
          else if (onRace != null)
            _RaceButton(onPressed: onRace!),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial, required this.selected});
  final String initial;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? NuvoColors.blue : NuvoColors.sectionBlue,
        border: selected
            ? Border.all(color: NuvoColors.blue, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.titleMedium.copyWith(
          color: selected ? NuvoColors.white : NuvoColors.blue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RaceButton extends StatelessWidget {
  const _RaceButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: NuvoColors.blue,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          'Race',
          style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.white),
        ),
      ),
    );
  }
}

class _SelectCircle extends StatelessWidget {
  const _SelectCircle({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? NuvoColors.blue : Colors.transparent,
        border: Border.all(
          color: selected ? NuvoColors.blue : NuvoColors.border,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}
