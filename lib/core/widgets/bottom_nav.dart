import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

const _kTrackNavy = Color(0xFF071B35);
const _kTrackActiveBlue = Color(0xFF2F7CFF);

class NuvoBottomNav extends StatelessWidget {
  const NuvoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isDark = false,
    this.rowKey,
  });

  final bool isDark;
  final Key? rowKey;

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double _surfaceHeight = 64;
  static const double _darkHeight = 64;
  static const double _horizontalMargin = 16;
  static const double _topReserve = 6;
  static const double _bottomGapNoInset = 10;
  static const double _bottomGapWithInset = 8;
  static const double _shadowReserve = 2;
  static const double _contentGap = 8;

  static double bottomPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return _occupiedHeight(safeBottom) + _contentGap;
  }

  static double _occupiedHeight(double safeBottom) {
    final bottomGap = safeBottom == 0 ? _bottomGapNoInset : _bottomGapWithInset;
    return _topReserve +
        _surfaceHeight +
        bottomGap +
        safeBottom +
        _shadowReserve;
  }

  static const _items = [
    _NavItem(asset: 'assets/branding/trans.png', label: 'Arena'),
    _NavItem(icon: Icons.emoji_events_outlined, label: 'Compete'),
    _NavItem(icon: Icons.gpp_good_outlined, label: 'Verify'),
    _NavItem(icon: Icons.group_outlined, label: 'Crew'),
    _NavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomGap = safeBottom == 0 ? _bottomGapNoInset : _bottomGapWithInset;
    final dockBottom = safeBottom + bottomGap + _shadowReserve;

    if (isDark) {
      return Container(
        height: _darkHeight + safeBottom,
        color: _kTrackNavy,
        padding: EdgeInsets.only(bottom: safeBottom),
        child: Row(
          key: rowKey,
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
      height: _occupiedHeight(safeBottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: _surfaceHeight,
          margin: EdgeInsets.fromLTRB(
            _horizontalMargin,
            0,
            _horizontalMargin,
            dockBottom,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.lg),
            border: Border.all(color: NuvoColors.divider, width: 1),
            boxShadow: AppShadows.softSubtle,
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
                minWidth: isDark ? 44 : 48,
                minHeight: isDark ? 36 : 48,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isDark ? 4 : 6,
                vertical: isDark ? 4 : 6,
              ),
              decoration: isDark
                  ? null
                  : BoxDecoration(
                      color: selected
                          ? NuvoColors.panel
                          : CupertinoColors.transparent,
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
                  if (item.asset != null && isDark)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: ClipRect(
                        child: OverflowBox(
                          maxWidth: 48,
                          maxHeight: 48,
                          child: Image.asset(
                            item.asset!,
                            height: 48,
                            color: labelColor,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                      ),
                    )
                  else if (item.asset != null)
                    Image.asset(
                      item.asset!,
                      height: 24,
                      color: labelColor,
                      colorBlendMode: BlendMode.srcIn,
                    )
                  else
                    Icon(item.icon!, size: isDark ? 20 : 22, color: labelColor),
                  SizedBox(height: isDark ? 2 : 3),
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
    final pressedOffset = _pressed ? 2.0 : 0.0;
    final width = widget.selected ? 60.0 : 58.0;
    final height = widget.selected ? 56.0 : 54.0;

    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: SizedBox(
          width: 68,
          height: 62,
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(
                pressedOffset,
                pressedOffset,
                0,
              ),
              width: width,
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: NuvoColors.actionBlue,
                borderRadius: BorderRadius.circular(NuvoRadii.button),
                border: Border.all(color: NuvoColors.navy, width: 1.5),
                boxShadow: _pressed ? null : AppShadows.softSubtle,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.item.icon, size: 22, color: NuvoColors.white),
                  const SizedBox(height: 3),
                  Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: const TextScaler.linear(1),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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
