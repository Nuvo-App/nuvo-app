import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// One tab in [V13TabBar].
class V13TabItem {
  const V13TabItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
  });

  final String label;
  final IconData icon;

  /// Filled variant shown while active — falls back to [icon].
  final IconData? selectedIcon;
}

/// The v13 floating dock: a white pill with the 2 px navy outline and hard
/// shadow, inset from the screen edges and sized to its four slots. It sits
/// just above the home indicator; page content scrolls behind it. The active
/// tab gets a filled blue icon and label over a soft blue capsule that
/// glides between slots on the v13 spring.
///
/// GEOMETRY CONTRACT — the shell passes this as `bottomNavigationBar` with
/// `extendBody: true`, so body `MediaQuery.padding.bottom` already equals
/// the dock's full footprint (dock + gap + safe inset). Screens pad their
/// last row by [bottomPadding], which adds the clearance on top of that.
class V13TabBar extends StatelessWidget {
  const V13TabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<V13TabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  // ── Geometry contract ──────────────────────────────────────────────────

  /// Visual height of the dock pill (inside its outline).
  static const double barHeight = 60;

  /// Breathing strip reserved above the dock's top edge.
  static const double topBreath = 8;

  /// Section gap reserved below a scroll view's last row, on top of the dock.
  static const double scrollClearance = 16;

  /// Widest a tab slot gets — the dock hugs its content instead of
  /// running edge to edge.
  static const double maxSlotWidth = 76;

  /// Minimum side gap between the dock and the screen edges.
  static const double sideInset = 16;

  static const double _inner = 4;

  /// Slot width for a screen [width]: [maxSlotWidth], shrunk on narrow
  /// phones (iPhone SE 1st gen) so the dock always keeps [sideInset].
  static double slotWidthFor(double width, int count) {
    final room = width - sideInset * 2 - (V13.outline + _inner) * 2;
    return math.min(maxSlotWidth, room / count);
  }

  /// Gap between the dock and the bottom edge when there's no home indicator.
  static const double _minBottomGap = 12;

  /// The shared bottom-content inset every scroll view pads its last row by.
  static double bottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + topBreath + scrollClearance;

  /// Distance from the screen's bottom edge to the dock's bottom edge: the
  /// dock rides just above the home indicator instead of above its full
  /// safe inset, which would float it too high.
  static double dockBottomGap(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;
    return math.max(safe - 8, _minBottomGap);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final index = currentIndex.clamp(0, items.length - 1);
    const inner = _inner;
    final slotWidth = slotWidthFor(
      MediaQuery.sizeOf(context).width,
      items.length,
    );

    return Padding(
      padding: EdgeInsets.only(
        top: topBreath,
        bottom: dockBottomGap(context),
      ),
      child: Center(
        heightFactor: 1,
        child: Container(
          key: const ValueKey('v13-dock'),
          decoration: BoxDecoration(
            color: V13.card,
            borderRadius: BorderRadius.circular(V13.radiusPill),
            border: Border.all(color: V13.navy, width: V13.outline),
            boxShadow: V13.shadow4,
          ),
          padding: const EdgeInsets.all(inner),
          child: SizedBox(
            height: barHeight - inner * 2,
            width: slotWidth * items.length,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: reduce ? Duration.zero : V13Motion.medium,
                  curve: V13Motion.spring,
                  left: slotWidth * index,
                  top: 0,
                  bottom: 0,
                  width: slotWidth,
                  child: Container(
                    key: const ValueKey('v13-tab-indicator'),
                    decoration: BoxDecoration(
                      color: V13.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(V13.radiusPill),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      SizedBox(
                        width: slotWidth,
                        child: _TabSlot(
                          key: ValueKey('v13-tab-slot-$i'),
                          item: items[i],
                          selected: i == index,
                          onTap: () {
                            V13Haptics.select();
                            onTap(i);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final V13TabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? V13.blue : V13.muted;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: reduce ? Duration.zero : V13Motion.fast,
              curve: V13Motion.spring,
              child: Icon(
                selected ? (item.selectedIcon ?? item.icon) : item.icon,
                size: 22,
                color: fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: V13.label.copyWith(
                color: fg,
                fontSize: 10,
                letterSpacing: 0.4,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }
}
