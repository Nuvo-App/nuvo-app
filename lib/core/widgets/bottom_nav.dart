import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class NuvoBottomNav extends StatelessWidget {
  const NuvoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const items = [
    (Icons.grid_view_rounded, 'Arena'),
    (Icons.group_rounded, 'Crew'),
    (Icons.add_circle_rounded, 'Compete'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF07152B), width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1407152B),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalW = constraints.maxWidth;
            // Selected tab is twice as wide as each unselected tab.
            // total = 2u + 3u = 5u → u = total / 5
            final unit = totalW / 5.0;
            final selectedW = unit * 2.0;
            final unselectedW = unit;

            return Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    width: i == currentIndex ? selectedW : unselectedW,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: _NavButton(
                      icon: items[i].$1,
                      label: items[i].$2,
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? NuvoColors.icyBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: selected
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: NuvoColors.blue, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: const Color(0xFF07152B),
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ],
              )
            : Center(child: Icon(icon, color: NuvoColors.muted, size: 20)),
      ),
    );
  }
}
