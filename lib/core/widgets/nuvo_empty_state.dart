import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_button.dart';

/// The one empty-state pattern for the whole app: a colour-tinted icon tile, a
/// headline, an instructional line that tells the person exactly what to do,
/// and a primary (plus optional secondary) action.
///
/// Never render a blank area or a bare "Nothing here". Every empty state uses
/// this and says what to tap.
class NuvoEmptyState extends StatelessWidget {
  const NuvoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
    this.secondaryLabel,
    this.onSecondary,
    this.accent = NuvoColors.blue,
    this.align = TextAlign.start,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Tints the icon tile. Pick something that fits the section (blue default,
  /// green for "done", amber for "waiting", …).
  final Color accent;

  /// [TextAlign.center] for a full-screen state, [TextAlign.start] when it
  /// sits inline in a left-aligned column (the common case).
  final TextAlign align;

  /// Smaller icon tile + tighter spacing, for inline use inside a section.
  final bool compact;

  bool get _center => align == TextAlign.center;

  @override
  Widget build(BuildContext context) {
    final tile = compact ? 44.0 : 52.0;
    final column = Column(
      crossAxisAlignment:
          _center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: tile,
          height: tile,
          decoration: BoxDecoration(
            color: _roleSurface(accent),
            borderRadius: BorderRadius.circular(NuvoRadii.md),
            border: Border.all(color: _roleBorder(accent)),
          ),
          child: Icon(icon, size: compact ? 20 : 24, color: accent),
        ),
        SizedBox(height: compact ? 14 : 18),
        Text(
          title,
          style: (compact ? AppTextStyles.titleLarge : AppTextStyles.headlineMedium)
              .copyWith(color: NuvoColors.navy),
          textAlign: align,
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          textAlign: align,
        ),
        if (ctaLabel != null && onCta != null) ...[
          SizedBox(height: compact ? 16 : 22),
          NuvoPrimaryButton(
            label: ctaLabel!,
            expand: !_center,
            small: compact,
            onPressed: onCta,
          ),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 8),
            NuvoSecondaryButton(
              label: secondaryLabel!,
              expand: !_center,
              small: compact,
              onPressed: onSecondary,
            ),
          ],
        ],
      ],
    );

    if (!_center) return column;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: column,
        ),
      ),
    );
  }
}

Color _roleSurface(Color accent) => switch (accent) {
  NuvoColors.success => NuvoColors.successSurface,
  NuvoColors.danger => NuvoColors.dangerSurface,
  NuvoColors.warning => NuvoColors.warningSurface,
  _ => NuvoColors.blueSurface,
};

Color _roleBorder(Color accent) => switch (accent) {
  NuvoColors.success => NuvoColors.successBorder,
  NuvoColors.danger => NuvoColors.dangerBorder,
  NuvoColors.warning => NuvoColors.warningBorder,
  _ => NuvoColors.blueBorder,
};
