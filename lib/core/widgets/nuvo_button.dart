import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
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
        strokeWidth: 2,
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
        Icon(icon, color: textColor, size: 17),
      ],
    ],
  );
}

// ── NuvoPrimaryButton ─────────────────────────────────────────────────────────

/// Gradient blue CTA button — the primary action element.
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
    final height = small ? 44.0 : 54.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1.0 : 0.42,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: enabled ? NuvoColors.blue : NuvoColors.paleSlate,
            borderRadius: BorderRadius.circular(small ? 16 : 18),
            border: Border.all(color: NuvoColors.navy, width: 2),
            boxShadow: enabled ? AppShadows.actionShadow : null,
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

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

// Alias kept for backward compatibility.
class NuvoBlueButton extends NuvoPrimaryButton {
  const NuvoBlueButton({
    super.key,
    required super.label,
    super.onPressed,
    super.icon,
    super.expand,
    super.loading,
    super.small,
  });
}

// ── NuvoOutlineButton ─────────────────────────────────────────────────────────

/// Clean white button with soft slate border — secondary action.
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
    final height = small ? 44.0 : 54.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1.0 : 0.46,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: NuvoColors.white,
            borderRadius: BorderRadius.circular(small ? 14 : 16),
            border: Border.all(
              color: NuvoColors.navy.withValues(alpha: 0.22),
              width: 1.2,
            ),
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

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

typedef NuvoSecondaryButton = NuvoOutlineButton;

// ── NuvoGhostButton ───────────────────────────────────────────────────────────

/// Light panel fill — tertiary / low-emphasis action.
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
    final height = small ? 40.0 : 48.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1.0 : 0.46,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: NuvoColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NuvoColors.border, width: 1),
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

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

// ── NuvoDangerButton ──────────────────────────────────────────────────────────

/// Light danger-tinted button with danger border — destructive actions.
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
    final height = small ? 44.0 : 54.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1.0 : 0.46,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: NuvoColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: NuvoColors.danger.withValues(alpha: 0.38),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: _buttonContent(
            label: label,
            textColor: NuvoColors.danger,
            icon: icon,
            loading: loading,
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

// ── NuvoBackButton ────────────────────────────────────────────────────────────

/// Clean white circle back button with a soft shadow.
class NuvoBackButton extends StatelessWidget {
  const NuvoBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: NuvoColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: NuvoColors.navy.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
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

/// White circle icon action button — top-bar and contextual actions.
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
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: NuvoColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: NuvoColors.navy.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: iconColor, size: 19),
            if (badge)
              Positioned(
                top: 9,
                right: 9,
                child: Container(
                  width: 7,
                  height: 7,
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
