import 'package:flutter/material.dart';
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
    _NavItem(label: 'Arena', isArena: true),
    _NavItem(icon: Icons.emoji_events_outlined, label: 'Compete'),
    _NavItem(icon: Icons.verified_user_outlined, label: 'Verify'),
    _NavItem(icon: Icons.group_outlined, label: 'Crew'),
    _NavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final dockBottom = safeBottom == 0 ? 0.0 : safeBottom;
    final dockHeight = visual.style == NuvoPreviewStyle.trackside ? 74.0 : 69.0;

    return SizedBox(
      height: dockHeight + dockBottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: dockHeight,
          margin: EdgeInsets.only(bottom: dockBottom),
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 6),
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
  const _NavItem({this.icon, required this.label, this.isArena = false});

  final IconData? icon;
  final String label;
  final bool isArena;
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
    final inactiveColor = visual.style == NuvoPreviewStyle.trackside
        ? visual.onNavigation.withValues(alpha: 0.92)
        : visual.onNavigation;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: 1,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: const BoxDecoration(color: Colors.transparent),
            child: Column(
              mainAxisAlignment: visual.style == NuvoPreviewStyle.trackside
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 28,
                  child: item.isArena
                      ? ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            selected ? activeColor : inactiveColor,
                            BlendMode.srcIn,
                          ),
                          child: Transform.scale(
                            scale: 2.1,
                            child: Image.asset(
                              'assets/branding/trans.png',
                              width: 27,
                              height: 27,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        )
                      : Icon(
                          item.icon,
                          size: 25,
                          color: selected ? activeColor : inactiveColor,
                        ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: selected ? activeColor : inactiveColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
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
