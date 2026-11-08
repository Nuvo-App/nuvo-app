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

/// The v13 bottom tab bar: white and outlined (a 2 px navy line across the
/// top), four slots with icon + label, and a blue indicator dash that
/// slides to the active slot on the v13 spring.
///
/// GEOMETRY CONTRACT — mirrors `NuvoBottomNav` so it can drop into the
/// same shell: [barHeight] is the visual height, the bar adds the bottom
/// safe inset below that, and [bottomPadding] is the shared scroll inset
/// every screen pads its last row by.
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

  /// Visual height of the bar, above the bottom safe inset.
  static const double barHeight = 62;

  /// Breathing strip above the bar's top edge.
  static const double topBreath = 8;

  /// Section gap reserved below a scroll view's last row, on top of the bar.
  static const double scrollClearance = 10;

  /// The shared bottom-content inset — same formula as
  /// `NuvoBottomNav.bottomPadding`.
  static double bottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + topBreath + scrollClearance;

  static const double _indicatorW = 28;
  static const double _indicatorH = 4;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final index = currentIndex.clamp(0, items.length - 1);

    return Container(
      decoration: const BoxDecoration(
        color: V13.card,
        border: Border(
          top: BorderSide(color: V13.navy, width: V13.outline),
        ),
      ),
      padding: EdgeInsets.only(bottom: safeBottom),
      child: SizedBox(
        height: barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slotW = constraints.maxWidth / items.length;
            return Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
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
                AnimatedPositioned(
                  duration: reduce ? Duration.zero : V13Motion.medium,
                  curve: V13Motion.spring,
                  left: slotW * index + (slotW - _indicatorW) / 2,
                  bottom: 5,
                  width: _indicatorW,
                  height: _indicatorH,
                  child: Container(
                    decoration: BoxDecoration(
                      color: V13.blue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            );
          },
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
    final fg = selected ? V13.navy : V13.muted;
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
            Icon(
              selected ? (item.selectedIcon ?? item.icon) : item.icon,
              size: 24,
              color: fg,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: V13.label.copyWith(
                color: fg,
                fontSize: 10,
                letterSpacing: 0.6,
              ),
              maxLines: 1,
            ),
            // Reserve the indicator's lane so labels never collide with it.
            const SizedBox(height: V13TabBar._indicatorH + 5),
          ],
        ),
      ),
    );
  }
}
