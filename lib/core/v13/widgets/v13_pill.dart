import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_pressable.dart';

/// Static status pill — "Live now", "In 2 days", place tags. Not tappable;
/// wrap in [V13Pressable] or use [V13Chip] for selection UI.
class V13Pill extends StatelessWidget {
  const V13Pill({
    super.key,
    required this.label,
    this.color = V13.card,
    this.textColor = V13.navy,
    this.icon,
  });

  final String label;
  final Color color;
  final Color textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: V13.caption.copyWith(
                color: textColor,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable chip — filter rows, mode picks, favorite movements.
/// Selected = navy fill + small shadow; unselected = outlined white.
/// [auto] pins a mini "auto" tag after the label (the composer marks
/// autofilled values this way).
class V13Chip extends StatelessWidget {
  const V13Chip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.auto = false,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool auto;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? V13.card : V13.navy;
    final radius = BorderRadius.circular(V13.radiusPill);
    final chip = Container(
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.symmetric(
        horizontal: V13.gapLg,
        vertical: V13.gapSm,
      ),
      decoration: BoxDecoration(
        color: selected ? V13.navy : V13.card,
        borderRadius: radius,
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: V13.bodyStrong.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (auto) ...[const SizedBox(width: 6), const V13AutoTag()],
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      child: V13Pressable(
        onTap: onTap,
        shadow: selected ? V13.shadow3 : null,
        borderRadius: radius,
        pressDepth: 2,
        haptic: onTap != null,
        enabled: onTap != null,
        child: chip,
      ),
    );
  }
}

/// The mini "auto" tag pinned onto autofilled values.
class V13AutoTag extends StatelessWidget {
  const V13AutoTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: V13.lilac,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: 1.5),
      ),
      child: Text(
        'auto',
        style: V13.label.copyWith(
          color: V13.navy,
          fontSize: 9,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
