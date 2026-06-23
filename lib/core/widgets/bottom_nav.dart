import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'pressable_scale.dart';

// ── Tab definitions ───────────────────────────────────────────────────────────
// Indices map to shell paths in main_shell.dart:
// 0 → /arena, 1 → /compete (Races), 2 → /move, 3 → /pass (Crew), 4 → /profile

class NuvoBottomNav extends StatelessWidget {
  const NuvoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    _NavItem(icon: Icons.bolt_rounded,       label: 'Arena'),
    _NavItem(icon: Icons.flag_rounded,        label: 'Races'),
    _NavItem(icon: Icons.add_rounded,         label: 'Move',  isCta: true),
    _NavItem(icon: Icons.group_rounded,       label: 'Crew'),
    _NavItem(icon: Icons.person_rounded,      label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      color: NuvoColors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top hairline divider
          Container(height: 1, color: NuvoColors.divider),
          Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SizedBox(
              height: 58,
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: _NavButton(
                        item: _items[i],
                        selected: i == currentIndex,
                        onTap: () => onTap(i),
                        index: i,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.label,
    this.isCta = false,
  });

  final IconData icon;
  final String label;
  final bool isCta;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.index,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    // Center CTA button (Move) — raised circle
    if (item.isCta) {
      return PressableScale(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected ? NuvoColors.navy : NuvoColors.blue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                item.icon,
                color: NuvoColors.white,
                size: 22,
                weight: 600,
              ),
            ),
          ],
        ),
      );
    }

    // Regular tab
    final isActive = selected;
    final iconColor = isActive ? NuvoColors.navy : NuvoColors.muted;
    final labelColor = isActive ? NuvoColors.navy : NuvoColors.muted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: iconColor, size: 22),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: AppTextStyles.labelSmall.copyWith(
              color: labelColor,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
