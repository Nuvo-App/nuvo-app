import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
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

  /// The total vertical space the dock occupies from the bottom of the screen.
  /// Use this as bottom padding in scrollable screens that sit behind the nav.
  static double bottomPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final dockBottom = safeBottom == 0 ? 8.0 : safeBottom - 2;
    const dockHeight = 52.0;
    const topClearance = 8.0;
    return dockHeight + dockBottom + topClearance + 6;
  }

  static const _items = [
    _NavItem(icon: CupertinoIcons.bolt_fill, label: 'Arena'),
    _NavItem(icon: CupertinoIcons.flag_fill, label: 'Compete'),
    _NavItem(icon: CupertinoIcons.camera_fill, label: 'Verify', center: true),
    _NavItem(icon: CupertinoIcons.person_2_fill, label: 'Crew'),
    _NavItem(icon: CupertinoIcons.person_fill, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final dockBottom = safeBottom == 0 ? 8.0 : safeBottom - 2;
    const dockHeight = 52.0;
    const topClearance = 8.0;

    return SizedBox(
      height: dockHeight + dockBottom + topClearance,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 16,
            right: 16,
            bottom: dockBottom,
            child: Container(
              height: dockHeight,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: NuvoColors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: NuvoColors.navy, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: NuvoColors.navy2.withValues(alpha: 0.08),
                    blurRadius: 16,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _NavButton(
                      item: _items[i],
                      selected: currentIndex == i,
                      center: _items[i].center,
                      onTap: () => _tap(i),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _tap(int index) {
    HapticFeedback.lightImpact();
    onTap(index);
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.label,
    this.center = false,
  });

  final IconData icon;
  final String label;
  final bool center;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.center,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool center;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (center) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 50,
                height: 46,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  border: Border.all(color: NuvoColors.navy, width: 1.5),
                  boxShadow: AppShadows.actionShadow,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.camera_fill,
                      size: 19,
                      color: NuvoColors.white,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final color = selected
        ? NuvoColors.navy
        : NuvoColors.navy.withValues(alpha: 0.58);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 52,
            height: 42,
            decoration: BoxDecoration(
              color: selected
                  ? NuvoColors.navy.withValues(alpha: 0.08)
                  : CupertinoColors.transparent,
              borderRadius: BorderRadius.circular(NuvoRadii.md),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, size: 19, color: color),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
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
