import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_motion.dart';

// Was bespoke #071B35/#2F7CFF — now the shared dark trackside bar color,
// matching the dark page so the bar doesn't sit as a navy slab over
// camera/proof surfaces.
const _kTrackNavy = NuvoColors.darkPage;
const _kTrackActiveBlue = NuvoColors.blue;

/// One root destination of the app shell. THE canonical tab table: the
/// order of [nuvoDestinations] IS the index contract — nav highlight,
/// `MainShell`'s route mapping, the `StatefulShellRoute` branch order, and
/// `NuvoTabStack`'s transition direction all derive from this single list.
/// 0 Arena · 1 Compete · 2 Crew · 3 Profile.
///
/// There is no Verify tab: starting a proof lives on Race Detail
/// (`/race/:id`), `/race/:id/proof` and `/race/:id/proof/ai-motion`.
class NuvoDestination {
  const NuvoDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const nuvoDestinations = <NuvoDestination>[
  NuvoDestination(
    path: '/arena',
    label: 'Arena',
    icon: Icons.stadium_outlined,
    selectedIcon: Icons.stadium,
  ),
  NuvoDestination(
    path: '/compete',
    label: 'Compete',
    icon: Icons.emoji_events_outlined,
    selectedIcon: Icons.emoji_events,
  ),
  NuvoDestination(
    path: '/pass',
    label: 'Crew',
    icon: Icons.group_outlined,
    selectedIcon: Icons.group,
  ),
  NuvoDestination(
    path: '/profile',
    label: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];

/// Bottom navigation for Nuvo.
///
/// CONNECTED BAR: the nav is a full-width, flush-bottom iOS-style tab bar
/// (one surface, 1px top hairline, safe inset absorbed inside). `MainShell`
/// hosts it with `Scaffold(bottomNavigationBar: ..., extendBody: true)`:
/// page content extends to the bottom edge and scrolls behind the opaque bar.
///
/// Because the body extends behind/around the dock, [bottomPadding] is the
/// contract every scrollable screen applies to its final padding so the
/// last row can scroll fully clear of the dock instead of hiding behind it.
///
/// GEOMETRY CONTRACT (single source of truth):
///   navDockHeight — the dock's visual height (52pt incl. 1px hairline), above the safe inset.
///   navScrollClearance — the one section gap below a screen's last row.
///   bottomPadding(context) = MediaQuery.padding.bottom + navScrollClearance
///
/// The dock's bottom edge sits exactly on the device bottom inset — nothing
/// is drawn inside the home-indicator gesture zone, and the inset is never
/// doubled into the dock's own height. Scaffold reports the dock's total
/// rendered height (dock + inset) through the body's `padding.bottom`, so
/// screens cannot double-count the shell.
///
/// CONTENT FIT MATH (per tab): icon(20) + gap(1) + label(~11) ≈ 32px inside
/// navDockHeight(58). Every Expanded cell is a full-height, 1/4-width tap
/// target (≥44px) regardless of how quiet the visuals are.
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

  /// The dock's visual height — compact by design. Content owns the screen.
  static const double navDockHeight = 52;

  /// Breathing strip above the bar — none: the bar is flush and hairlined.
  static const double navTopBreath = 0;

  /// Content height of the dark trackside bar (non-shell screens).
  static const double navContentHeight = 48;

  /// Section gap reserved below a scroll view's last row, on top of the dock.
  /// Deliberately small — it separates content from the dock, it does not
  /// double the dock's height.
  static const double navScrollClearance = 10;

  /// The one shared bottom-content inset every scrollable screen uses for
  /// its final padding. MUST be called with a context inside the shell body
  /// (all four tab screens qualify): Scaffold already inflates that context's
  /// `padding.bottom` by the nav's full rendered height — dock plus device
  /// safe inset — so adding those again here would double-count the shell.
  /// That double-count was the old "white shelf": it reserved
  /// bar + (bar + inset) + a large gap under every tab.
  ///
  /// With `extendBody: true` the page continues to the screen edge, so this
  /// reserves the dock's full height, the breathing strip above it, plus the
  /// section gap — the last row always scrolls clear instead of ending
  /// behind the dock.
  static double bottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom +
      navTopBreath +
      navScrollClearance;

  /// Nav items derive from the canonical [nuvoDestinations] table — never
  /// maintain a parallel destination list.
  static final _items = [
    for (final d in nuvoDestinations)
      _NavItem(icon: d.icon, selectedIcon: d.selectedIcon, label: d.label),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    if (isDark) {
      return Container(
        height: navContentHeight + safeBottom,
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
                isDark: true,
                onTap: () => _tap(index),
              ),
          ],
        ),
      );
    }

    // Connected bar: full width, flush to the screen bottom, one surface with
    // a 1px top hairline. The home-indicator inset is absorbed inside the
    // bar's own background so no strip of page colour shows under it.
    final colors = context.themeColors;
    return Container(
      height: navDockHeight + safeBottom,
      padding: EdgeInsets.only(bottom: safeBottom),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider, width: 1)),
      ),
      child: Row(
        key: rowKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < _items.length; index++)
            _NavButton(
              item: _items[index],
              selected: currentIndex == index,
              isDark: false,
              onTap: () => _tap(index),
            ),
        ],
      ),
    );
  }

  void _tap(int index) {
    HapticFeedback.selectionClick();
    onTap(index);
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// One equal-width destination: a full-height tap cell holding an icon in a
/// soft blue capsule (selected) over a one-line label. Selection reads through
/// the capsule, the filled icon, Nuvo blue, and a heavier label — never
/// colour alone.
class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final inactiveColor = widget.isDark
        ? NuvoColors.white.withValues(alpha: 0.75)
        : context.themeColors.inkMuted;
    final activeColor = widget.isDark
        ? _kTrackActiveBlue
        : context.themeColors.accent;

    return Expanded(
      child: Semantics(
        selected: widget.selected,
        button: true,
        label: widget.item.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.94 : 1.0,
              duration: NuvoMotion.pressIn,
              curve: Curves.easeOut,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: widget.selected ? 1.0 : 0.0),
                duration: NuvoMotion.select,
                curve: NuvoMotion.settle,
                builder: (context, t, _) {
                  final color = Color.lerp(inactiveColor, activeColor, t)!;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        key: widget.selected
                            ? const ValueKey('nuvo-nav-indicator')
                            : null,
                        width: 48,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: activeColor.withValues(alpha: 0.14 * t),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          widget.selected
                              ? widget.item.selectedIcon
                              : widget.item.icon,
                          size: 22,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: const TextScaler.linear(1),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: color,
                          fontSize: 10,
                          fontWeight: widget.selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
