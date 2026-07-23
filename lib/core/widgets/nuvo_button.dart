import 'package:flutter/material.dart';

import '../design/nuvo_preview_style.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'pressable_scale.dart';

Widget _buttonContent({
  required String label,
  required Color textColor,
  IconData? icon,
  Widget? leadingWidget,
  bool loading = false,
}) {
  if (loading) {
    return SizedBox(
      width: 19,
      height: 19,
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
      if (leadingWidget != null) ...[leadingWidget, const SizedBox(width: 9)],
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelLarge.copyWith(
            color: textColor,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
      if (icon != null) ...[
        const SizedBox(width: 8),
        Icon(icon, color: textColor, size: 17),
      ],
    ],
  );
}

Widget _buttonShell({
  required Widget child,
  required VoidCallback? onTap,
  required bool enabled,
  required double height,
  required double radius,
  required Color color,
  Color? borderColor,
  bool expand = false,
  List<BoxShadow>? shadows,
}) {
  final button = PressableScale(
    onTap: enabled ? onTap : null,
    scale: 0.975,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: expand ? double.infinity : null,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: borderColor == null ? null : Border.all(color: borderColor),
          boxShadow: shadows,
        ),
        child: child,
      ),
    ),
  );

  return expand ? SizedBox(width: double.infinity, child: button) : button;
}

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
    final visual = NuvoVisualTheme.of(context);
    final enabled = onPressed != null && !loading;
    return _buttonShell(
      height: small ? 44 : 54,
      radius: small ? 16 : 18,
      color: enabled ? visual.action : NuvoColors.paleSlate,
      shadows: enabled ? AppShadows.actionShadow : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        label: label,
        textColor: NuvoColors.white,
        icon: icon,
        leadingWidget: leadingWidget,
        loading: loading,
      ),
    );
  }
}

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

typedef NuvoBackplateButton = NuvoPrimaryButton;

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
    final visual = NuvoVisualTheme.of(context);
    final enabled = onPressed != null;
    return _buttonShell(
      height: small ? 44 : 54,
      radius: small ? 16 : 18,
      color: visual.surface,
      borderColor: visual.border,
      shadows: enabled ? AppShadows.hardShadow3 : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        label: label,
        textColor: visual.ink,
        icon: icon,
        leadingWidget: leadingWidget,
      ),
    );
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
    final visual = NuvoVisualTheme.of(context);
    final enabled = onPressed != null;
    return _buttonShell(
      height: small ? 40 : 48,
      radius: 16,
      color: visual.surfaceMuted,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(label: label, textColor: visual.ink, icon: icon),
    );
  }
}

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
    return _buttonShell(
      height: small ? 44 : 54,
      radius: small ? 16 : 18,
      color: NuvoColors.danger.withValues(alpha: 0.09),
      borderColor: NuvoColors.danger.withValues(alpha: 0.22),
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        label: label,
        textColor: NuvoColors.danger,
        icon: icon,
        loading: loading,
      ),
    );
  }
}

class NuvoBackButton extends StatelessWidget {
  const NuvoBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onPressed,
      scale: 0.94,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: NuvoColors.border),
          boxShadow: AppShadows.hardShadow3,
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
      scale: 0.94,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: NuvoColors.border),
          boxShadow: AppShadows.hardShadow3,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: iconColor, size: 19),
            if (badge)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: NuvoColors.coral,
                    shape: BoxShape.circle,
                    border: Border.all(color: NuvoColors.surface, width: 1.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
