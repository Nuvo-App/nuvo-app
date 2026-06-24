import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'pressable_scale.dart';

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _buttonContent({
  required String label,
  required Color textColor,
  IconData? icon,
  Widget? leadingWidget,
  bool loading = false,
}) {
  if (loading) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        valueColor: AlwaysStoppedAnimation(textColor),
      ),
    );
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (leadingWidget != null) ...[leadingWidget, const SizedBox(width: 10)],
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelLarge.copyWith(color: textColor),
        ),
      ),
      if (icon != null) ...[
        const SizedBox(width: 8),
        Icon(icon, color: textColor, size: 18),
      ],
    ],
  );
}

// ── NuvoPrimaryButton ─────────────────────────────────────────────────────────
/// Main CTA — navy gradient fill, white text. One per screen.
class NuvoPrimaryButton extends StatelessWidget {
  const NuvoPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leadingWidget,
    this.expand = false,
    this.loading = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leadingWidget;
  final bool expand;
  final bool loading;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final height = small ? 44.0 : 56.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D2040), NuvoColors.navy],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: _buttonContent(
            label: label,
            textColor: NuvoColors.white,
            icon: icon,
            leadingWidget: leadingWidget,
            loading: loading,
          ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

// ── NuvoBlueButton ────────────────────────────────────────────────────────────
/// Blue gradient CTA — the single blue focal point on a screen.
class NuvoBlueButton extends StatelessWidget {
  const NuvoBlueButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.loading = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool loading;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final height = small ? 44.0 : 56.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B7FFF), NuvoColors.blue],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: NuvoColors.blue.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: _buttonContent(
            label: label,
            textColor: NuvoColors.white,
            icon: icon,
            loading: loading,
          ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

// ── NuvoOutlineButton ─────────────────────────────────────────────────────────
/// Outline CTA — white fill, navy border. Secondary actions.
class NuvoOutlineButton extends StatelessWidget {
  const NuvoOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leadingWidget,
    this.expand = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leadingWidget;
  final bool expand;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final height = small ? 44.0 : 56.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: NuvoColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NuvoColors.navy, width: 1.5),
          ),
          alignment: Alignment.center,
          child: _buttonContent(
            label: label,
            textColor: NuvoColors.navy,
            icon: icon,
            leadingWidget: leadingWidget,
          ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

/// Alias — same as NuvoOutlineButton.
typedef NuvoSecondaryButton = NuvoOutlineButton;

// ── NuvoGhostButton ───────────────────────────────────────────────────────────
/// Ghost CTA — panel fill, muted navy text. Tertiary actions.
class NuvoGhostButton extends StatelessWidget {
  const NuvoGhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final height = small ? 44.0 : 56.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: NuvoColors.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NuvoColors.border),
          ),
          alignment: Alignment.center,
          child: _buttonContent(
            label: label,
            textColor: NuvoColors.navy,
            icon: icon,
          ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

// ── NuvoDangerButton ──────────────────────────────────────────────────────────
class NuvoDangerButton extends StatelessWidget {
  const NuvoDangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.small = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool small;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final height = small ? 44.0 : 56.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NuvoColors.danger),
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(NuvoColors.danger),
                  ),
                )
              : _buttonContent(
                  label: label,
                  textColor: NuvoColors.danger,
                  icon: icon,
                ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

// ── NuvoBackButton ────────────────────────────────────────────────────────────
/// Circular back button — 44px, panel fill, navy arrow.
class NuvoBackButton extends StatelessWidget {
  const NuvoBackButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: NuvoColors.panel,
          shape: BoxShape.circle,
          border: Border.all(color: NuvoColors.border),
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: NuvoColors.navy,
          size: 20,
        ),
      ),
    );
  }
}

// ── NuvoIconAction ────────────────────────────────────────────────────────────
/// Small 44×44 icon tap target — panel fill, border.
class NuvoIconAction extends StatelessWidget {
  const NuvoIconAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor = NuvoColors.navy,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: NuvoColors.panel,
          shape: BoxShape.circle,
          border: Border.all(color: NuvoColors.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: iconColor, size: 20),
            if (badge)
              Positioned(
                top: 9,
                right: 9,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: NuvoColors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
