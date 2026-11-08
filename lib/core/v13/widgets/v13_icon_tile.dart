import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_pressable.dart';

/// Rounded-square tile in one of the palette colors with a navy icon —
/// movement badges, settings row icons, crew tiles.
class V13IconTile extends StatelessWidget {
  const V13IconTile({
    super.key,
    required this.icon,
    this.color = V13.sky,
    this.size = 44,
    this.radius = V13.radiusTile,
    this.iconColor = V13.navy,
    this.iconSize,
    this.onTap,
    this.semanticLabel,
  });

  final IconData icon;

  /// Tile fill — a race/crew palette color.
  final Color color;
  final double size;
  final double radius;
  final Color iconColor;

  /// Defaults to `size * 0.5`.
  final double? iconSize;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: Icon(icon, size: iconSize ?? size * 0.5, color: iconColor),
    );

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: V13Pressable(
        onTap: onTap,
        enabled: onTap != null,
        haptic: onTap != null,
        shadow: V13.shadow3,
        borderRadius: borderRadius,
        semanticLabel: semanticLabel,
        child: tile,
      ),
    );
  }
}
