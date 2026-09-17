import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';

// Was bespoke #071B35/#2F7CFF — now the one navy/blue everywhere, per the
// design guide's "4-5 colors used for almost everything" rule (matches the
// fix in track_view_screen.dart's trackside chrome).
const _kTrackNavy = NuvoColors.navy;
const _kTrackActiveBlue = NuvoColors.blue;

/// Bottom navigation for Nuvo.
///
/// GEOMETRY CONTRACT:
///   _dockHeight         — visible dock container height
///   _dockPadding        — internal vertical padding
///   _dockInternal       — usable height inside dock (= _dockHeight - _dockPadding*2)
///   _verifyRise         — how far Verify extends above the dock top edge
///   _topReserve         — space above dock for Verify rise + breathing
///   _bottomGap*         — gap between dock bottom and screen bottom (excl. safe area)
///   _contentGap         — extra breathing room between dock top and page content
///
/// Every scrollable page MUST use [NuvoBottomNav.bottomPadding] as its bottom
/// inset. This guarantees no content is ever obscured by the dock.
///
/// CONTENT FIT MATH (normal button):
///   icon(20) + spacing(2) + label(11) + padding(5*2) = 43px
///   Must be <= _dockInternal (50px) → 7px headroom ✓
///
/// CONTENT FIT MATH (Verify button):
///   icon(18) + spacing(2) + label(11) + padding(5*2) = 41px
///   AnimatedContainer height = 50px → fits in _dockInternal
///   Verify SizedBox = _dockInternal + _verifyRise = 50 + 10 = 60px
///   Aligned topCenter → rises 10px above dock, 0px below
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

  // ── Geometry contract ──────────────────────────────────────────────────────
  static const double _dockHeight = 64;
  static const double _dockPadding = 7;
  static const double _dockInternal = _dockHeight - _dockPadding * 2; // 50
  static const double _verifyRise = 10;
  static const double _topReserve =
      _verifyRise + 4; // 14 — Verify rise + breathing
  static const double _bottomGapNoInset = 10;
  static const double _bottomGapWithInset = 8;
  static const double _contentGap = 8;
  static const double _horizontalMargin = 16;

  // Dark mode (Arena) uses a simpler full-width bar.
  static const double _darkHeight = 60;

  /// The bottom padding every scrollable page must use.
  /// Ensures content can scroll completely above the dock.
  static double bottomPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return _occupiedHeight(safeBottom) + _contentGap;
  }

  static double _occupiedHeight(double safeBottom) {
    final bottomGap = safeBottom == 0 ? _bottomGapNoInset : _bottomGapWithInset;
    return _topReserve + _dockHeight + bottomGap + safeBottom;
  }

  static const _items = [
    _NavItem(icon: Icons.stadium_outlined, label: 'Arena'),
    _NavItem(icon: Icons.emoji_events_outlined, label: 'Compete'),
    _NavItem(icon: Icons.gpp_good_outlined, label: 'Verify'),
    _NavItem(icon: Icons.group_outlined, label: 'Crew'),
    _NavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomGap = safeBottom == 0 ? _bottomGapNoInset : _bottomGapWithInset;

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
          height: _dockHeight,
          margin: EdgeInsets.fromLTRB(
            _horizontalMargin,
            0,
            _horizontalMargin,
            bottomGap + safeBottom,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: _dockPadding,
          ),
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.lg),
            border: Border.all(color: NuvoColors.divider, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
  const _NavItem({this.icon, required this.label}) : asset = null;

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
        child: Align(
          alignment: Alignment.topCenter,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: isDark
                  ? null
                  : BoxDecoration(
                      color: selected
                          ? NuvoColors.panel
                          : CupertinoColors.transparent,
                      borderRadius: BorderRadius.circular(NuvoRadii.md),
                      border: selected
                          ? Border.all(
                              color: NuvoColors.blue.withValues(alpha: 0.15),
                              width: 1,
                            )
                          : null,
                    ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (item.asset != null && isDark)
                    SizedBox(
                      width: 22,
                      height: 22,
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
                      height: 20,
                      color: labelColor,
                      colorBlendMode: BlendMode.srcIn,
                    )
                  else
                    Icon(item.icon!, size: isDark ? 20 : 20, color: labelColor),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: const TextScaler.linear(1),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: labelColor,
                      fontSize: isDark ? 10 : 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      height: 1.1,
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
    final pressedOffset = _pressed ? 1.5 : 0.0;
    // AnimatedContainer fits inside dock internal height.
    // SizedBox is taller by _verifyRise so the button rises above the dock.
    final containerHeight = NuvoBottomNav._dockInternal; // 50
    final sizedBoxHeight =
        NuvoBottomNav._dockInternal + NuvoBottomNav._verifyRise; // 60

    // Verify keeps its distinctive raised-shield shape whether selected or
    // not — but only the *current* tab may read as active. Selected: solid
    // blue, white content (unmistakably "on"). Unselected: plain surface
    // fill, quiet ink content, thin neutral border — the same "off" register
    // every other tab uses, just in this button's own shape.
    final fill = widget.selected ? NuvoColors.actionBlue : NuvoColors.surface;
    final border = widget.selected ? NuvoColors.navy : NuvoColors.border;
    final borderWidth = widget.selected ? 1.25 : 1.0;
    final content = widget.selected ? NuvoColors.white : NuvoColors.textMuted;

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
          width: 56,
          height: sizedBoxHeight,
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
              width: 52,
              height: containerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(NuvoRadii.button),
                border: Border.all(color: border, width: borderWidth),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.item.icon, size: 18, color: content),
                  const SizedBox(height: 2),
                  Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: const TextScaler.linear(1),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: content,
                      fontSize: 10,
                      fontWeight: widget.selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      height: 1.1,
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
