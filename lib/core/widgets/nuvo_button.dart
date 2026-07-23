import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
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
          style: AppTextStyles.buttonLabel.copyWith(color: textColor),
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
  double borderWidth = 2,
  bool expand = false,
  List<BoxShadow>? shadows,
}) {
  final button = _PhysicalButtonShell(
    onTap: onTap,
    enabled: enabled,
    height: height,
    radius: radius,
    color: color,
    borderColor: borderColor,
    borderWidth: borderWidth,
    expand: expand,
    shadows: shadows,
    child: child,
  );

  return expand ? SizedBox(width: double.infinity, child: button) : button;
}

class _PhysicalButtonShell extends StatefulWidget {
  const _PhysicalButtonShell({
    required this.child,
    required this.onTap,
    required this.enabled,
    required this.height,
    required this.radius,
    required this.color,
    required this.borderWidth,
    this.borderColor,
    this.expand = false,
    this.shadows,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double height;
  final double radius;
  final Color color;
  final Color? borderColor;
  final double borderWidth;
  final bool expand;
  final List<BoxShadow>? shadows;

  @override
  State<_PhysicalButtonShell> createState() => _PhysicalButtonShellState();
}

class _PhysicalButtonShellState extends State<_PhysicalButtonShell> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final pressedOffset = _pressed ? 4.0 : 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: widget.enabled ? 1 : 0.58,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(pressedOffset, pressedOffset, 0),
          width: widget.expand ? double.infinity : null,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(widget.radius),
            border: widget.borderColor == null
                ? null
                : Border.all(
                    color: widget.borderColor!,
                    width: widget.borderWidth,
                  ),
            boxShadow: _pressed ? null : widget.shadows,
          ),
          child: widget.child,
        ),
      ),
    );
  }
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
    final enabled = onPressed != null && !loading;
    return _buttonShell(
      height: small ? 46 : 56,
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: enabled ? NuvoColors.actionBlue : NuvoColors.disabledSurface,
      borderColor: enabled ? NuvoColors.navy : NuvoColors.border,
      shadows: enabled ? AppShadows.hardMedium : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        label: label,
        textColor: enabled ? NuvoColors.white : NuvoColors.disabledText,
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
    final enabled = onPressed != null;
    return _buttonShell(
      height: small ? 46 : 56,
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: NuvoColors.surface,
      borderColor: enabled ? NuvoColors.navy : NuvoColors.border,
      shadows: enabled ? AppShadows.hardSmall : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        label: label,
        textColor: NuvoColors.navy,
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
    final enabled = onPressed != null;
    return _buttonShell(
      height: small ? 42 : 50,
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: Colors.transparent,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        label: label,
        textColor: NuvoColors.navy,
        icon: icon,
      ),
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
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: NuvoColors.danger.withValues(alpha: 0.09),
      borderColor: NuvoColors.danger,
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
          border: Border.all(color: NuvoColors.navy, width: 2),
          boxShadow: AppShadows.hardSmall,
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
          color: NuvoColors.panelLight,
          shape: BoxShape.circle,
          border: Border.all(color: NuvoColors.border, width: 1.25),
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
