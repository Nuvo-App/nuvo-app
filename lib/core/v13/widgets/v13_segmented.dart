import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// One segment of [V13Segmented].
class V13Segment {
  const V13Segment({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

/// Segmented control ("Camera / Manual", "This week / All time"). The navy
/// indicator pill slides between segments on the v13 spring.
class V13Segmented extends StatelessWidget {
  const V13Segmented({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 44,
    this.semanticLabel,
  });

  final List<V13Segment> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: semanticLabel,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: V13.card,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segW = constraints.maxWidth / segments.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: reduce ? Duration.zero : V13Motion.medium,
                  curve: V13Motion.spring,
                  left: segW * selectedIndex.clamp(0, segments.length - 1),
                  top: 0,
                  bottom: 0,
                  width: segW,
                  child: Container(
                    decoration: BoxDecoration(
                      color: V13.navy,
                      borderRadius: BorderRadius.circular(V13.radiusPill),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < segments.length; i++)
                      Expanded(
                        child: _SegmentSlot(
                          segment: segments[i],
                          selected: i == selectedIndex,
                          onTap: () {
                            V13Haptics.select();
                            onChanged(i);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SegmentSlot extends StatelessWidget {
  const _SegmentSlot({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final V13Segment segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? V13.card : V13.navy;
    return Semantics(
      button: true,
      selected: selected,
      label: segment.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (segment.icon != null) ...[
                Icon(segment.icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  segment.label,
                  style: V13.bodyStrong.copyWith(color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
