import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_pressable.dart';

/// The v13 list divider — a thin 2 px line between open rows.
class V13Divider extends StatelessWidget {
  const V13Divider({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.color = V13.divider,
    this.thickness = 2,
  });

  final double indent;
  final double endIndent;
  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, right: endIndent),
      child: ColoredBox(
        color: color,
        child: SizedBox(height: thickness, width: double.infinity),
      ),
    );
  }
}

/// An open list row — content with a thin 2 px divider under it, never a
/// boxed card. Lists in v13 are stacks of these.
class V13ListRow extends StatelessWidget {
  const V13ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.padding,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The divider under the row — last row in a list passes false.
  final bool showDivider;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: V13.gapMd + 2),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: V13.gapMd)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: V13.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: V13.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: V13.gapMd),
            trailing!,
          ],
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        V13Pressable(
          onTap: onTap,
          pressDepth: 2,
          haptic: onTap != null,
          enabled: onTap != null,
          semanticLabel: semanticLabel ?? title,
          child: row,
        ),
        if (showDivider) const V13Divider(),
      ],
    );
  }
}
