import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../design/nuvo_preview_style.dart';
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
    final visual = NuvoVisualTheme.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final dockBottom = safeBottom == 0 ? 0.0 : safeBottom;

    return SizedBox(
      height: 70 + dockBottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 70,
          margin: EdgeInsets.only(bottom: dockBottom),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
          decoration: BoxDecoration(
            color: visual.navigation,
            border: Border(top: BorderSide(color: visual.border)),
          ),
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                _NavButton(
                  item: _items[index],
                  selected: currentIndex == index,
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
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final activeColor = visual.action;
    final inactiveColor = visual.onNavigation.withValues(alpha: 0.58);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1 : 0.97,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: CupertinoColors.transparent,
              border: Border(
                top: BorderSide(
                  color: selected ? activeColor : CupertinoColors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSlide(
                  offset: selected ? const Offset(0, -0.08) : Offset.zero,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    item.icon,
                    size: selected ? 21 : 19,
                    color: selected ? activeColor : inactiveColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: selected ? activeColor : inactiveColor,
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
