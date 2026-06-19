import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'pressable_scale.dart';

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
  // Optional widget shown on the left of the label (e.g. brand icon for auth buttons).
  final Widget? leadingWidget;
  final bool expand;
  final bool loading;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final height = small ? 42.0 : 56.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: NuvoColors.blue,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              // Hard navy offset backplate — Nuvo card depth effect
              BoxShadow(
                color: Color(0xB007152B),
                blurRadius: 0,
                offset: Offset(4, 5),
              ),
              // Blue ambient glow
              BoxShadow(
                color: Color(0x33075BFF),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(NuvoColors.white),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (leadingWidget != null) ...[
                      leadingWidget!,
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: NuvoColors.white,
                        ),
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, color: NuvoColors.white, size: 19),
                    ],
                  ],
                ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

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
    final height = small ? 42.0 : 56.0;

    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: NuvoColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NuvoColors.navy, width: 1.6),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leadingWidget != null) ...[
                leadingWidget!,
                const SizedBox(width: 10),
              ],
              if (icon != null) ...[
                Icon(icon, color: NuvoColors.navy, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: NuvoColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

typedef NuvoSecondaryButton = NuvoOutlineButton;

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
    final height = small ? 40.0 : 52.0;
    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: NuvoColors.icyBlue,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NuvoColors.border),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: NuvoColors.blue, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: NuvoColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

class NuvoDangerButton extends StatelessWidget {
  const NuvoDangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final button = PressableScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEF1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5484D), width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3307152B),
                blurRadius: 0,
                offset: Offset(3, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: const Color(0xFFE5484D), size: 18),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: const Color(0xFFE5484D),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

class NuvoIconAction extends StatelessWidget {
  const NuvoIconAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = PressableScale(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A07152B),
              blurRadius: 0,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: Icon(icon, color: NuvoColors.navy, size: 20),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

typedef NuvoBackplateButton = NuvoPrimaryButton;
