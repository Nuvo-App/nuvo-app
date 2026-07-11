import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'nuvo_button.dart';

/// Compatibility wrapper for old call sites. New code should use
/// [NuvoPrimaryButton] or [NuvoOutlineButton] directly.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.height = 56,
    this.color = NuvoColors.blue,
  });

  /// Convenience constructor for completed/verified surfaces.
  const GradientButton.victory({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.height = 56,
  }) : color = NuvoColors.success;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NuvoPrimaryButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      expand: expand,
      small: height <= 48,
    );
  }
}
