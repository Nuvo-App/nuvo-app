import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_pressable.dart';

enum V13ButtonVariant { primary, secondary, ghost, danger }

enum V13ButtonSize { small, medium, large }

/// The v13 button. Primary blue is reserved for the one main action per
/// screen; secondary is the outlined white button; ghost is text-only;
/// danger is destructive red.
///
/// Press behavior comes from [V13Pressable]: the surface sinks onto its
/// shadow plate and springs back with a light haptic. [loading] swaps the
/// label for a spinner and blocks the tap.
class V13Button extends StatelessWidget {
  const V13Button({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = V13ButtonVariant.primary,
    this.size = V13ButtonSize.medium,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  });

  const V13Button.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = V13ButtonSize.medium,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  }) : variant = V13ButtonVariant.primary;

  const V13Button.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = V13ButtonSize.medium,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  }) : variant = V13ButtonVariant.secondary;

  const V13Button.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.size = V13ButtonSize.medium,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  }) : variant = V13ButtonVariant.ghost;

  const V13Button.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.size = V13ButtonSize.medium,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  }) : variant = V13ButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final V13ButtonVariant variant;
  final V13ButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;
  final String? semanticLabel;

  double get _height => switch (size) {
    V13ButtonSize.small => 40,
    V13ButtonSize.medium => 52,
    V13ButtonSize.large => 60,
  };

  double get _fontSize => switch (size) {
    V13ButtonSize.small => 13,
    V13ButtonSize.medium => 15,
    V13ButtonSize.large => 16,
  };

  @override
  Widget build(BuildContext context) {
    final interactive = onPressed != null && !loading;
    final fill = switch (variant) {
      V13ButtonVariant.primary => interactive ? V13.blue : V13.bg,
      V13ButtonVariant.danger => interactive ? V13.danger : V13.bg,
      V13ButtonVariant.secondary => V13.card,
      V13ButtonVariant.ghost => V13.card.withValues(alpha: 0),
    };
    final fg = switch (variant) {
      V13ButtonVariant.primary ||
      V13ButtonVariant.danger => interactive ? V13.card : V13.muted,
      _ => interactive ? V13.navy : V13.muted,
    };
    final outlined = variant != V13ButtonVariant.ghost;
    final shadow = outlined && interactive ? V13.shadow4 : null;
    final borderRadius = BorderRadius.circular(V13.radiusButton);

    final textStyle = V13.buttonLabel.copyWith(fontSize: _fontSize, color: fg);

    Widget content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              strokeCap: StrokeCap.round,
              color: fg,
            ),
          )
        else ...[
          if (icon != null) ...[
            Icon(icon, size: _fontSize + 4, color: fg),
            const SizedBox(width: V13.gapSm),
          ],
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    content = Container(
      height: _height,
      width: fullWidth ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: size == V13ButtonSize.small ? V13.gapLg : V13.gapXl,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: outlined
            ? Border.all(color: V13.navy, width: V13.outline)
            : null,
      ),
      child: content,
    );

    return V13Pressable(
      onTap: interactive ? onPressed : null,
      enabled: interactive,
      shadow: shadow,
      borderRadius: borderRadius,
      pressDepth: outlined ? null : 2,
      semanticLabel: semanticLabel ?? label,
      child: content,
    );
  }
}

/// Outlined icon-only button for headers and rows — round or rounded-square,
/// optional coral badge count.
class V13IconButton extends StatelessWidget {
  const V13IconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.shape = V13IconButtonShape.round,
    this.badgeCount,
    this.semanticLabel,
    this.size = 44,
    this.color = V13.card,
    this.iconColor = V13.navy,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final V13IconButtonShape shape;

  /// Coral count badge pinned to the top-right. Hidden when null or <= 0;
  /// counts above 9 render as "9+".
  final int? badgeCount;
  final String? semanticLabel;
  final double size;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final interactive = onTap != null;
    final radius = shape == V13IconButtonShape.round
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(V13.radiusTile);

    Widget button = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: interactive ? color : V13.bg,
        borderRadius: radius,
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: interactive ? iconColor : V13.muted,
      ),
    );

    final badge = badgeCount;
    if (badge != null && badge > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: V13.coral,
                borderRadius: BorderRadius.circular(V13.radiusPill),
                border: Border.all(color: V13.navy, width: V13.outline),
              ),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: V13.label.copyWith(
                  color: V13.navy,
                  fontSize: 10,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return V13Pressable(
      onTap: onTap,
      shadow: interactive ? V13.shadow3 : null,
      borderRadius: radius,
      semanticLabel: semanticLabel,
      child: button,
    );
  }
}

enum V13IconButtonShape { round, square }
