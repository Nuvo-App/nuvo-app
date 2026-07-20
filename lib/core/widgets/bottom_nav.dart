import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

class NuvoBottomNav extends StatelessWidget {
  const NuvoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static double bottomPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return 68 + (safeBottom == 0 ? 12 : safeBottom) + 14;
  }

  static const _items = [
    _NavItem(icon: CupertinoIcons.bolt_fill, label: 'Arena'),
    _NavItem(icon: CupertinoIcons.flag_fill, label: 'Compete'),
    _NavItem(icon: CupertinoIcons.camera_fill, label: 'Verify'),
    _NavItem(icon: CupertinoIcons.person_2_fill, label: 'Crew'),
    _NavItem(icon: CupertinoIcons.person_fill, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final dockBottom = safeBottom == 0 ? 12.0 : safeBottom - 2;

    return SizedBox(
      height: 68 + dockBottom + 12,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 68,
          margin: EdgeInsets.fromLTRB(16, 0, 16, dockBottom),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                NuvoColors.surface,
                NuvoColors.surface,
                NuvoColors.icyBlue,
              ],
              stops: [0, 0.68, 1],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: NuvoColors.border),
            boxShadow: AppShadows.dockShadow,
          ),
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                _NavButton(
                  item: _items[index],
                  selected: currentIndex == index,
                  isPrimary: index == 2,
                  onTap: () => _tap(index),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _tap(int index) {
    HapticFeedback.selectionClick();
    onTap(index);
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
    required this.isPrimary,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = isPrimary ? NuvoColors.surface : NuvoColors.blue;
    final inactiveColor = NuvoColors.textMuted;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: isPrimary ? 1.03 : (selected ? 1 : 0.97),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            margin: isPrimary
                ? const EdgeInsets.symmetric(horizontal: 2)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: isPrimary
                  ? NuvoColors.actionBlue
                  : selected
                  ? NuvoColors.icyBlue
                  : CupertinoColors.transparent,
              borderRadius: BorderRadius.circular(NuvoRadii.md),
              border: selected && !isPrimary
                  ? Border.all(color: NuvoColors.border)
                  : null,
              boxShadow: isPrimary
                  ? AppShadows.brandGlow(intensity: 1.2)
                  : selected
                  ? AppShadows.brandGlow(intensity: 0.55)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSlide(
                  offset: selected ? const Offset(0, -0.08) : Offset.zero,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    item.icon,
                    size: isPrimary || selected ? 20 : 19,
                    color: isPrimary || selected ? activeColor : inactiveColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isPrimary || selected ? activeColor : inactiveColor,
                    fontSize: 9.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
