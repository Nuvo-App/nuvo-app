import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

/// Nuvo's single unified floating light navigation.
///
/// Used identically by all five tabs — Arena, Compete, Verify, Crew, Profile.
/// There is no dark variant: Nuvo has one light application theme.
class NuvoBottomNav extends StatelessWidget {
  const NuvoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.rowKey,
  });

  final Key? rowKey;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Height of the visible floating pill.
  static const double _surfaceHeight = 64;

  /// Horizontal inset of the pill from the screen edges.
  static const double _horizontalMargin = 16;

  /// Gap above the pill so shadows and scroll content never collide.
  static const double _topReserve = 8;

  /// Gap below the pill when the device has no home-indicator inset.
  static const double _bottomGapNoInset = 12;

  /// Gap below the pill when the device has a home indicator.
  static const double _bottomGapWithInset = 6;

  /// Extra room reserved for the soft drop shadow.
  static const double _shadowReserve = 4;

  /// Breathing room between the last scrollable item and the pill.
  static const double _contentGap = 12;

  /// Bottom padding scroll views must apply so their final item clears the nav.
  ///
  /// Uses `viewPaddingOf` rather than `paddingOf`: a Scaffold with
  /// `extendBody: true` consumes the body's `padding.bottom`, which would make
  /// screens under-pad by exactly the home-indicator inset and let the last row
  /// slide under the pill. `viewPadding` always reports the true device inset,
  /// so the screen and the nav agree on the same number.
  static double bottomPadding(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return _occupiedHeight(safeBottom) + _contentGap;
  }

  static double _occupiedHeight(double safeBottom) {
    final bottomGap = safeBottom == 0 ? _bottomGapNoInset : _bottomGapWithInset;
    return _topReserve + _surfaceHeight + bottomGap + safeBottom + _shadowReserve;
  }

  static const _items = [
    _NavItem(icon: Icons.stadium_outlined, activeIcon: Icons.stadium, label: 'Arena'),
    _NavItem(
        icon: Icons.emoji_events_outlined,
        activeIcon: Icons.emoji_events,
        label: 'Compete'),
    _NavItem(
        icon: Icons.verified_outlined, activeIcon: Icons.verified, label: 'Verify'),
    _NavItem(icon: Icons.group_outlined, activeIcon: Icons.group, label: 'Crew'),
    _NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomGap = safeBottom == 0 ? _bottomGapNoInset : _bottomGapWithInset;
    final dockBottom = safeBottom + bottomGap + _shadowReserve;

    return SizedBox(
      height: _occupiedHeight(safeBottom),
      child: Stack(
        children: [
          // Scrim: the page colour fades in beneath the pill so scrolling
          // content dissolves instead of being visibly sliced by the floating
          // bar or peeking out below it.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      NuvoColors.page.withValues(alpha: 0),
                      NuvoColors.page.withValues(alpha: 0.92),
                      NuvoColors.page,
                    ],
                    stops: const [0, 0.42, 0.68],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: _surfaceHeight,
              margin: EdgeInsets.fromLTRB(
                _horizontalMargin,
                0,
                _horizontalMargin,
                dockBottom,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: NuvoColors.surface,
                borderRadius: BorderRadius.circular(_surfaceHeight / 2),
                border: Border.all(color: NuvoColors.border, width: 1),
                boxShadow: AppShadows.navBar,
              ),
              child: Row(
                key: rowKey,
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
        ],
      ),
    );
  }

  void _tap(int index) {
    if (index == currentIndex) return;
    HapticFeedback.selectionClick();
    onTap(index);
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = selected ? NuvoColors.blue : NuvoColors.textMuted;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // A 44x44 minimum target is guaranteed by the 64px-tall pill and
          // the equal-width Expanded slot (390 - 32 - 12) / 5 = 69px.
          child: Center(
            child: AnimatedContainer(
              duration: Duration(milliseconds: reduceMotion ? 0 : 160),
              curve: Curves.easeOut,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selected
                    ? NuvoColors.blue.withValues(alpha: 0.09)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? item.activeIcon : item.icon,
                    size: 22,
                    color: color,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    textScaler: const TextScaler.linear(1),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: color,
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      height: 1,
                      letterSpacing: 0,
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
