import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

/// A pill-shaped CTA that fills with the brand gradient and casts a soft
/// brand-colored glow on press/focus.
///
/// Behaves like a [FilledButton] (handles disabled state, taps, padding) but
/// honors Nuvo's brand language instead of a flat fill.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.gradient = AppGradients.brand,
    this.expand = false,
    this.height = 56,
  });

  /// Convenience constructor for victory/success surfaces.
  const GradientButton.victory({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.height = 56,
  }) : gradient = AppGradients.victory;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final LinearGradient gradient;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      height: height,
      decoration: BoxDecoration(
        gradient: disabled ? null : gradient,
        color: disabled ? Theme.of(context).colorScheme.surface : null,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: disabled ? const [] : AppShadows.brandGlow(intensity: 0.7),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(height / 2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.black87),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
