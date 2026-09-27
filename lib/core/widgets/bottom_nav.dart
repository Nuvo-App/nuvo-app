import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
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
/// 0 Arena · 1 Compete · 2 Verify · 3 Crew · 4 Profile.
class NuvoDestination {
  const NuvoDestination({
    required this.path,
    required this.label,
    required this.icon,
  });

  final String path;
  final String label;
  final IconData icon;
}

const nuvoDestinations = <NuvoDestination>[
  NuvoDestination(
    path: '/arena',
    label: 'Arena',
    icon: Icons.stadium_outlined,
  ),
  NuvoDestination(
    path: '/compete',
    label: 'Compete',
    icon: Icons.emoji_events_outlined,
  ),
  NuvoDestination(
    path: '/move',
    label: 'Verify',
    icon: Icons.gpp_good_outlined,
  ),
  NuvoDestination(path: '/pass', label: 'Crew', icon: Icons.group_outlined),
  NuvoDestination(
    path: '/profile',
    label: 'Profile',
    icon: Icons.person_outline,
  ),
];

/// Bottom navigation for Nuvo.
///
/// FLOATING DOCK: the nav is a compact white rounded container inset from
/// the screen edges — it behaves like a control, not a section of the
/// screen. `MainShell` hosts it with `Scaffold(bottomNavigationBar: ...,
/// extendBody: true)`: page content extends to the bottom edge and is
/// visible in the dock's horizontal margins while scrolling.
///
/// Because the body extends behind/around the dock, [bottomPadding] is the
/// contract every scrollable screen applies to its final padding so the
/// last row can scroll fully clear of the dock instead of hiding behind it.
///
/// GEOMETRY CONTRACT (single source of truth):
///   navDockHeight — the dock's visual height (58px), above the safe inset.
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
/// navDockHeight(58). Every Expanded cell is a full-height, 1/5-width tap
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
  static const double navDockHeight = 58;

  /// Horizontal margin between the dock and the screen edges.
  static const double navDockInset = 16;

  /// How far Verify's circle rises above the dock's top edge.
  static const double navVerifyRaise = 8;

  /// Content height of the dark trackside bar (non-shell screens).
  static const double navContentHeight = 48;

  /// Section gap reserved below a scroll view's last row, on top of the dock.
  /// Deliberately small — it separates content from the dock, it does not
  /// double the dock's height.
  static const double navScrollClearance = 10;

  /// The one shared bottom-content inset every scrollable screen uses for
  /// its final padding. MUST be called with a context inside the shell body
  /// (all five tab screens qualify): Scaffold already inflates that context's
  /// `padding.bottom` by the nav's full rendered height — dock plus device
  /// safe inset — so adding those again here would double-count the shell.
  /// That double-count was the old "white shelf": it reserved
  /// bar + (bar + inset) + a large gap under every tab.
  ///
  /// With `extendBody: true` the page continues to the screen edge, so this
  /// reserves the dock's full height, Verify's rise above the dock's top
  /// edge, plus the section gap — the last row always scrolls clear instead
  /// of ending behind the dock or the elevated circle.
  static double bottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom +
      navVerifyRaise +
      navScrollClearance;

  /// Nav items derive from the canonical [nuvoDestinations] table — never
  /// maintain a parallel destination list.
  static final _items = [
    for (final d in nuvoDestinations)
      _NavItem(icon: d.icon, label: d.label),
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
                isPrimary: false,
                isDark: true,
                onTap: () => _tap(index),
              ),
          ],
        ),
      );
    }

    // Floating dock — white rounded container inset from the edges, resting
    // directly on the safe inset. Nuvo structure comes from the thin navy
    // edge + offset navy shadow (the app's tactile shadow language), not
    // from a divider or a full-width surface.
    return Padding(
      padding: EdgeInsets.fromLTRB(navDockInset, 0, navDockInset, safeBottom),
      child: Container(
        height: navDockHeight,
        decoration: BoxDecoration(
          color: context.themeColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.hero),
          border: Border.all(color: context.themeColors.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: context.themeColors.inkShadow,
              blurRadius: 0,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          key: rowKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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

class _NavButton extends StatefulWidget {
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
    if (widget.isPrimary && !widget.isDark) {
      return Expanded(
        child: _VerifyNavButton(
          item: widget.item,
          selected: widget.selected,
          onTap: widget.onTap,
        ),
      );
    }

    // Selection is color + a small lift, not a capsule: the active
    // destination reads through Nuvo blue on icon + label and rises ~2px
    // while everyone else stays quiet ink.
    final inactiveColor = widget.isDark
        ? NuvoColors.white.withValues(alpha: 0.75)
        : context.themeColors.inkSubtle;
    final activeColor = widget.isDark ? _kTrackActiveBlue : NuvoColors.blue;

    // Expanded cell + opaque hit test: the whole 1/5-width, full-height cell
    // is the tap target. The visual stays compact and quiet inside it.
    return Expanded(
      child: Semantics(
        selected: widget.selected,
        button: true,
        label: widget.item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.92 : 1.0,
              duration: NuvoMotion.pressIn,
              curve: Curves.easeOut,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: widget.selected ? 1.0 : 0.0),
                duration: NuvoMotion.select,
                curve: NuvoMotion.settle,
                builder: (context, selected, _) {
                  final color =
                      Color.lerp(inactiveColor, activeColor, selected)!;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(0, -2 * selected),
                        child: _icon(color),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: const TextScaler.linear(1),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: color,
                          fontSize: 10,
                          fontWeight: widget.selected
                              ? FontWeight.w700
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

  Widget _icon(Color color) {
    if (widget.item.asset != null && widget.isDark) {
      return SizedBox(
        width: 20,
        height: 20,
        child: ClipRect(
          child: OverflowBox(
            maxWidth: 44,
            maxHeight: 44,
            child: Image.asset(
              widget.item.asset!,
              height: 44,
              color: color,
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
        ),
      );
    }
    if (widget.item.asset != null) {
      return Image.asset(
        widget.item.asset!,
        height: 20,
        color: color,
        colorBlendMode: BlendMode.srcIn,
      );
    }
    return Icon(widget.item.icon!, size: 20, color: color);
  }
}

/// Verify is Nuvo's central action — it gets the reference's center-action
/// treatment: a compact circle raised slightly above the dock's top edge.
/// The elevation is a few pixels of silhouette, not a FAB; the label stays at
/// the shared baseline with the other four destinations and the cell keeps
/// the same 1/5 width so neighbours never shift.
///
/// Inactive: navy circle, white icon — structural emphasis.
/// Active: Nuvo blue circle, white icon — unmistakably the current tab.
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

class _VerifyNavButtonState extends State<_VerifyNavButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  /// One-shot pulse when Verify becomes the active destination — a brief
  /// rise-and-settle on the circle, restrained (peak ~9%).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: NuvoMotion.select,
  );

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _VerifyNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    const circleSize = 40.0;
    final labelColor = widget.selected ? NuvoColors.blue : c.inkSubtle;

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
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Label pinned to the shared baseline — same position as every
            // other destination's label inside the dock.
            Positioned(
              left: 0,
              right: 0,
              bottom: 7,
              child: Center(
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: const TextScaler.linear(1),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: labelColor,
                    fontSize: 10,
                    fontWeight: widget.selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            // The elevated circle. Parent is the unclipped cell Stack, so the
            // circle can peek above the dock's top edge by [navVerifyRaise].
            Positioned(
              left: 0,
              right: 0,
              top: -NuvoBottomNav.navVerifyRaise,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    // Rise ~9% then settle back to exactly 1 — a physical
                    // "I'm active" acknowledgment, never a cartoon bounce.
                    final t = _pulse.value;
                    final pulse = 1 + 0.09 * (t < 0.5 ? t * 2 : (1 - t) * 2);
                    return Transform.scale(scale: pulse, child: child);
                  },
                  child: AnimatedScale(
                    scale: _pressed ? 0.92 : 1.0,
                    duration: NuvoMotion.pressIn,
                    curve: Curves.easeOut,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        // Unselected is a quiet ink disc on light; on dark
                        // surfaces navy vanishes, so the disc lifts to the
                        // raised panel tone instead.
                        end: widget.selected
                            ? NuvoColors.actionBlue
                            : (CupertinoTheme.brightnessOf(context) ==
                                    Brightness.dark
                                ? c.panel
                                : NuvoColors.navy),
                      ),
                      duration: NuvoMotion.select,
                      curve: Curves.easeOut,
                      builder: (context, fill, _) => Container(
                        width: circleSize,
                        height: circleSize,
                        decoration: BoxDecoration(
                          color: fill,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.border, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: c.inkShadow,
                              blurRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.item.icon,
                          size: 20,
                          color: NuvoColors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
