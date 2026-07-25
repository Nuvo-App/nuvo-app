import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';

import '../design/nuvo_preview_style.dart';
import '../theme/app_text_styles.dart';

const _kTrackNavy = Color(0xFF071B35);
const _kTrackActiveBlue = Color(0xFF2F7CFF);

class NuvoBottomNav extends StatelessWidget {
  const NuvoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isDark = false,
  });

  final bool isDark;

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double _surfaceHeight = 76;
  static const double _darkHeight = 75;
  static const double _horizontalMargin = 16;
  static const double _topReserve = 8;
  static const double _bottomGapNoInset = 10;
  static const double _bottomGapWithInset = 8;
  static const double _shadowReserve = 4;
  static const double _contentGap = 8;

  static double bottomPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return 68 + (safeBottom == 0 ? 12 : safeBottom) + 14;
  }

  static const _items = [
    _NavItem(asset: 'assets/branding/nuvoappicon.png', label: 'Arena'),
    _NavItem(icon: Icons.emoji_events_outlined, label: 'Compete'),
    _NavItem(icon: Icons.verified_outlined, label: 'Verify'),
    _NavItem(icon: Icons.group_outlined, label: 'Crew'),
    _NavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final dockBottom = safeBottom == 0 ? 0.0 : safeBottom;
    final dockHeight = visual.style == NuvoPreviewStyle.trackside ? 74.0 : 69.0;

    if (isDark) {
      return Container(
        height: _darkHeight,
        color: _kTrackNavy,
        padding: EdgeInsets.only(bottom: safeBottom),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var index = 0; index < _items.length; index++)
              _NavButton(
                item: _items[index],
                selected: currentIndex == index,
                isPrimary: false,
                isDark: true,
                onTap: () => _tap(index),
              ),
          ],
        ),
      );
    }

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
                  isPrimary: index == 2,
                  isDark: false,
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
  const _NavItem({this.icon, this.asset, required this.label});

  final IconData? icon;
  final String? asset;
  final String label;
  final bool isArena;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.isPrimary,
    required this.isDark,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool isPrimary;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isPrimary && !isDark) {
      return Expanded(
        child: Center(
          child: _VerifyNavButton(item: item, selected: selected, onTap: onTap),
        ),
      );
    }

    final color = isDark
        ? (selected ? _kTrackActiveBlue : NuvoColors.white)
        : (selected ? NuvoColors.blue : NuvoColors.textMuted);
    final alpha = selected ? 1.0 : (isDark ? 0.75 : 1.0);
    final labelColor = color.withValues(alpha: alpha);

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              constraints: BoxConstraints(
                minWidth: isDark ? 44 : 52,
                minHeight: isDark ? 36 : 54,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isDark ? 4 : 7,
                vertical: isDark ? 4 : 7,
              ),
              decoration: isDark
                  ? null
                  : BoxDecoration(
                      color: selected ? NuvoColors.panel : CupertinoColors.transparent,
                      borderRadius: BorderRadius.circular(NuvoRadii.md),
                      border: selected
                          ? Border.all(
                              color: NuvoColors.blue.withValues(alpha: 0.18),
                              width: 1.25,
                            )
                          : null,
                    ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (item.asset != null)
                    Image.asset(
                      item.asset!,
                      height: isDark ? 20 : 24,
                      color: labelColor,
                      colorBlendMode: BlendMode.srcIn,
                    )
                  else
                    Icon(
                      item.icon!,
                      size: isDark ? 20 : 24,
                      color: labelColor,
                    ),
                  SizedBox(height: isDark ? 2 : 4),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: const TextScaler.linear(1),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: labelColor,
                      fontSize: isDark ? 10 : 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
}

class _VerifyNavButton extends StatefulWidget {
  const _VerifyNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_VerifyNavButton> createState() => _VerifyNavButtonState();
}

class _VerifyNavButtonState extends State<_VerifyNavButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final pressedOffset = _pressed ? 3.5 : 0.0;
    final width = widget.selected ? 66.0 : 64.0;
    final height = widget.selected ? 62.0 : 60.0;

    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.item.label,
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
