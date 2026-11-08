import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_pressable.dart';

/// Section label — "YOUR RACES · 3" — in the tracked-out 11/800 micro
/// style, with an optional muted trailing link ("Swipe for more").
class V13SectionHeader extends StatelessWidget {
  const V13SectionHeader({
    super.key,
    required this.title,
    this.trailingLabel,
    this.onTrailingTap,
    this.trailing,
  });

  /// Rendered uppercased in the label style.
  final String title;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  /// Fully custom trailing widget; [trailingLabel]/[onTrailingTap] are the
  /// common case.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidget =
        trailing ??
        (trailingLabel == null
            ? null
            : V13Pressable(
                onTap: onTrailingTap,
                pressDepth: 1.5,
                haptic: onTrailingTap != null,
                enabled: onTrailingTap != null,
                semanticLabel: trailingLabel,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(trailingLabel!, style: V13.caption),
                ),
              ));

    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: V13.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailingWidget,
      ],
    );
  }
}
