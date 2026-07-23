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

  static const double _surfaceHeight = 76;
  static const double _horizontalMargin = 16;
  static const double _topReserve = 8;
  static const double _bottomGapNoInset = 10;
  static const double _bottomGapWithInset = 8;
  static const double _shadowReserve = 4;
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
    _NavItem(icon: CupertinoIcons.bolt_fill, label: 'Arena'),
    _NavItem(icon: CupertinoIcons.flag_fill, label: 'Compete'),
    _NavItem(icon: CupertinoIcons.camera_fill, label: 'Verify'),
    _NavItem(icon: CupertinoIcons.person_2_fill, label: 'Crew'),
    _NavItem(icon: CupertinoIcons.person_fill, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomGap = safeBottom == 0 ? _bottomGapNoInset : _bottomGapWithInset;
    final dockBottom = safeBottom + bottomGap + _shadowReserve;

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
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: NuvoColors.navy, width: 2),
            boxShadow: AppShadows.hardSmall,
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
    if (isPrimary) {
      return Expanded(
        child: Center(
          child: _VerifyNavButton(item: item, selected: selected, onTap: onTap),
        ),
      );
    }

    final color = selected ? NuvoColors.blue : NuvoColors.textMuted;

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
              constraints: const BoxConstraints(minWidth: 52, minHeight: 54),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
              decoration: BoxDecoration(
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
                  Icon(item.icon, size: 24, color: color),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: const TextScaler.linear(1),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: color,
                      fontSize: 11,
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
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: SizedBox(
          width: 74,
          height: 68,
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
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
              decoration: BoxDecoration(
                color: NuvoColors.actionBlue,
                borderRadius: BorderRadius.circular(NuvoRadii.button),
                border: Border.all(color: NuvoColors.navy, width: 2),
                boxShadow: _pressed ? null : AppShadows.hardSmall,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.item.icon, size: 25, color: NuvoColors.white),
                  const SizedBox(height: 4),
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
