import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

/// One root destination of the app shell. THE canonical tab table: the
/// order of [nuvoDestinations] IS the index contract — nav highlight,
/// `MainShell`'s route mapping, the `StatefulShellRoute` branch order, and
/// `NuvoTabStack`'s transition direction all derive from this single list.
/// 0 Arena · 1 Compete · 2 Friends · 3 Profile.
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
    label: 'Friends',
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

/// Bottom navigation for Nuvo: a FLOATING pill bar.
///
/// The bar is a rounded surface inset 16pt from the screen sides and lifted
/// [navDockGap] above the bottom safe inset. Four slots are spread evenly;
/// unselected slots show a thin outline icon only. The selected slot is a
/// dark pill (inverts in dark mode) holding the filled icon plus its label.
/// On selection change the pill grows out of a circle and the label slides
/// out from behind the icon, while the previous pill collapses back to an
/// icon. Reduce-motion makes the change instant.
///
/// GEOMETRY CONTRACT (single source of truth):
///   navDockHeight — the bar's visual height (64), above gap + inset.
///   navDockGap — space between the bar and the bottom safe inset.
///   The nav renders navDockHeight + navDockGap + safe inset in total;
///   `Scaffold(extendBody: true)` reports that through the body's
///   `padding.bottom`, so [bottomPadding] adds only the breath + clearance.
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

  // ── Geometry contract ──────────────────────────────────────────────────────

  /// The bar's visual height.
  static const double navDockHeight = 64;

  /// Gap between the bar's bottom edge and the bottom safe inset.
  static const double navDockGap = 10;

  /// Horizontal margin between the bar and the screen edges.
  static const double navDockInset = 16;

  /// Breathing strip above the bar's top edge (shadow + separation).
  static const double navTopBreath = 8;

  /// Section gap reserved below a scroll view's last row, on top of the bar.
  static const double navScrollClearance = 10;

  /// Tap target (and collapsed circle) size of one slot.
  static const double slotSize = 44;

  /// Label text scale ceiling inside the bar.
  static const double maxLabelScale = 1.3;

  /// The one shared bottom-content inset every scrollable screen uses. Call
  /// with a context inside the shell body: Scaffold already inflates its
  /// `padding.bottom` by the bar, gap and device inset, so only the breath
  /// above the bar and the section gap are added here.
  static double bottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + navTopBreath + navScrollClearance;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final colors = context.themeColors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxLabelScale);
    final labelStyle = AppTextStyles.labelLarge.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        navDockInset,
        0,
        navDockInset,
        safeBottom + navDockGap,
      ),
      child: Container(
        height: navDockHeight,
        // The app's signature physical treatment, same as buttons and cards: a
        // solid surface, an ink edge, and a hard-offset plate shadow (navy on
        // light, near-black on dark) — not a soft floating blur.
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(navDockHeight / 2),
          border: Border.all(color: colors.border, width: 2),
          boxShadow: AppShadows.hardOffset(colors.inkShadow),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final nav = nuvoDestinations;
            // The pill may use whatever the other three circles leave free.
            final maxPill =
                constraints.maxWidth - slotSize * (nav.length - 1) - 8;
            return Row(
              key: rowKey,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < nav.length; i++)
                  _NavSlot(
                    destination: nav[i],
                    selected: currentIndex == i,
                    maxWidth: maxPill,
                    reduceMotion: reduce,
                    labelStyle: labelStyle,
                    textScaler: scaler,
                    slotKey: ValueKey('nuvo-nav-slot-$i'),
                    pillKey: currentIndex == i
                        ? const ValueKey('nuvo-nav-indicator')
                        : null,
                    labelKey: ValueKey('nuvo-nav-label-$i'),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onTap(i);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavSlot extends StatefulWidget {
  const _NavSlot({
    required this.destination,
    required this.selected,
    required this.maxWidth,
    required this.reduceMotion,
    required this.labelStyle,
    required this.textScaler,
    required this.slotKey,
    required this.labelKey,
    required this.onTap,
    this.pillKey,
  });

  final NuvoDestination destination;
  final bool selected;
  final double maxWidth;
  final bool reduceMotion;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final Key slotKey;
  final Key? pillKey;
  final Key labelKey;
  final VoidCallback onTap;

  @override
  State<_NavSlot> createState() => _NavSlotState();
}

class _NavSlotState extends State<_NavSlot> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final d = widget.destination;
    const slot = NuvoBottomNav.slotSize;
    const icon = 24.0;
    const gap = 8.0;

    final painter = TextPainter(
      text: TextSpan(text: d.label, style: widget.labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: widget.textScaler,
      maxLines: 1,
    )..layout();
    // pill = 16 + icon + gap + label + 16, capped to the room available.
    final fullPill = (16 + icon + gap + painter.width + 16)
        .clamp(slot, double.infinity)
        .toDouble();
    final pillWidth = fullPill > widget.maxWidth ? widget.maxWidth : fullPill;
    final labelWidth = (pillWidth - 16 - icon - gap - 16).clamp(0.0, 400.0);
    painter.dispose();

    return Semantics(
      selected: widget.selected,
      button: true,
      label: d.label,
      excludeSemantics: true,
      child: GestureDetector(
        key: widget.slotKey,
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.selected ? 1.0 : 0.0),
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final width = slot + (pillWidth - slot) * t;
            // The selected pill is Nuvo's electric blue in both themes, with a
            // white icon + label (white on #1264FF is 4.9:1).
            final fg = Color.lerp(colors.inkMuted, NuvoColors.white, t)!;
            return SizedBox(
              height: NuvoBottomNav.navDockHeight,
              width: width.clamp(slot, double.infinity),
              child: Center(
                child: AnimatedScale(
                  scale: _pressed ? 0.94 : 1.0,
                  duration: const Duration(milliseconds: 90),
                  child: Container(
                    key: widget.pillKey,
                    width: width,
                    height: slot,
                    alignment: Alignment.center,
                    // Primary-button treatment: electric blue, ink edge, small
                    // hard plate. The edge is a foreground overlay so it never
                    // changes the pill's layout width.
                    decoration: BoxDecoration(
                      color: NuvoColors.blue.withValues(alpha: t),
                      borderRadius: BorderRadius.circular(slot / 2),
                      boxShadow: AppShadows.hardOffset(
                        colors.inkShadow.withValues(alpha: t),
                        offset: const Offset(2, 2),
                      ),
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(slot / 2),
                      border: Border.all(
                        color: colors.border.withValues(alpha: t),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRect(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            t > 0.5 ? d.selectedIcon : d.icon,
                            size: icon,
                            color: fg,
                          ),
                          if (t > 0)
                            ClipRect(
                              key: widget.labelKey,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: t,
                                child: Opacity(
                                  opacity: t,
                                  child: Transform.translate(
                                    offset: Offset(-8 * (1 - t), 0),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: gap),
                                      child: SizedBox(
                                        width: labelWidth,
                                        child: Text(
                                          d.label,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          textScaler: widget.textScaler,
                                          style: widget.labelStyle.copyWith(
                                            color: fg,
                                          ),
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
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
