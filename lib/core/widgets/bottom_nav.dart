import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

// Indices map to shell paths in main_shell.dart:
// 0 → /arena, 1 → /compete, 2 → /move, 3 → /pass (Crew), 4 → /profile

class NuvoBottomNav extends StatelessWidget {
  const NuvoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    _NavItem(icon: CupertinoIcons.bolt_fill, label: 'Arena'),
    _NavItem(icon: CupertinoIcons.flag_fill, label: 'Compete'),
    _NavItem(icon: CupertinoIcons.camera_fill, label: 'Move'),
    _NavItem(icon: CupertinoIcons.person_2_fill, label: 'Crew'),
    _NavItem(icon: CupertinoIcons.person_fill, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: 50 + bottom,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: NuvoColors.surface.withValues(alpha: 0.82),
              border: Border(
                top: BorderSide(
                  color: NuvoColors.navy.withValues(alpha: 0.08),
                ),
              ),
            ),
            padding: EdgeInsets.only(bottom: bottom),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  _NavButton(
                    item: _items[i],
                    selected: i == currentIndex,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onTap(i);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? NuvoColors.blue : NuvoColors.textDim;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
