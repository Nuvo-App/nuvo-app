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
          style: AppTextStyles.labelLarge.copyWith(
            color: textColor,
            fontWeight: FontWeight.w800,
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

/// Classic Nuvo hard-offset: outer solid plate, face inset right+bottom.
Widget _backplateButton({
  required double height,
  required double radius,
  required double offset,
  required Widget face,
  required VoidCallback? onTap,
  required bool enabled,
  Color plateColor = NuvoColors.inkNavy,
  bool expand = false,
}) {
  final shell = PressableScale(
    onTap: enabled ? onTap : null,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1.0 : 0.42,
      child: Container(
        width: expand ? double.infinity : null,
        decoration: BoxDecoration(
          color: plateColor,
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.only(right: offset, bottom: offset),
        child: SizedBox(height: height, child: face),
      ),
    ),
  );

  return expand ? SizedBox(width: double.infinity, child: shell) : shell;
}

// ── NuvoPrimaryButton ─────────────────────────────────────────────────────────

/// Royal-blue CTA with navy offset backplate.
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
    final radius = small ? 16.0 : 18.0;
    final offset = small ? 3.0 : 4.0;

    final face = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [NuvoColors.actionBlue, NuvoColors.blue2],
              )
            : null,
        color: enabled ? null : NuvoColors.paleSlate,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: NuvoColors.inkNavy, width: 2),
      ),
      alignment: Alignment.center,
      child: _buttonContent(
        label: label,
        textColor: NuvoColors.white,
        icon: icon,
        leadingWidget: leadingWidget,
        loading: loading,
      ),
    );

    return _backplateButton(
      height: height,
      radius: radius,
      offset: offset,
      face: face,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
    );
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

/// Alias for the classic backplate primary.
typedef NuvoBackplateButton = NuvoPrimaryButton;

// ── NuvoOutlineButton ─────────────────────────────────────────────────────────

/// White face + navy border + navy offset backplate.
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
    final radius = small ? 14.0 : 16.0;
    final offset = small ? 3.0 : 4.0;

    final face = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: NuvoColors.inkNavy, width: 2),
      ),
      alignment: Alignment.center,
      child: _buttonContent(
        label: label,
        textColor: NuvoColors.navy,
        icon: icon,
        leadingWidget: leadingWidget,
      ),
    );

    return _backplateButton(
      height: height,
      radius: radius,
      offset: offset,
      face: face,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
    );
  }
}

typedef NuvoSecondaryButton = NuvoOutlineButton;

// ── NuvoGhostButton ───────────────────────────────────────────────────────────

/// Icy panel face + navy offset backplate — tertiary action.
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
    const radius = 12.0;
    const offset = 3.0;

    final face = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: NuvoColors.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: NuvoColors.inkNavy, width: 2),
      ),
      alignment: Alignment.center,
      child: _buttonContent(
        label: label,
        textColor: NuvoColors.navy,
        icon: icon,
      ),
    );

    return _backplateButton(
      height: height,
      radius: radius,
      offset: offset,
      face: face,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
    );
  }
}

// ── NuvoDangerButton ──────────────────────────────────────────────────────────

/// White face + danger border + navy offset backplate.
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
    const radius = 14.0;
    const offset = 4.0;

    final face = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: NuvoColors.danger, width: 2),
      ),
      alignment: Alignment.center,
      child: _buttonContent(
        label: label,
        textColor: NuvoColors.danger,
        icon: icon,
        loading: loading,
      ),
    );

    return _backplateButton(
      height: height,
      radius: radius,
      offset: offset,
      face: face,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
    );
  }
}

// ── NuvoBackButton ────────────────────────────────────────────────────────────

/// Round pale circle with navy offset backplate.
class NuvoBackButton extends StatelessWidget {
  const NuvoBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    const offset = 3.0;

    return PressableScale(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(right: offset, bottom: offset),
        child: SizedBox(
          width: size + offset,
          height: size + offset,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: offset,
                top: offset,
                child: Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    color: NuvoColors.inkNavy,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: NuvoColors.panel,
                  shape: BoxShape.circle,
                  border: Border.all(color: NuvoColors.inkNavy, width: 2),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: NuvoColors.navy,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── NuvoIconAction ────────────────────────────────────────────────────────────

/// White circle icon action with navy offset backplate.
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
    const size = 42.0;
    const offset = 3.0;

    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: offset, bottom: offset),
        child: SizedBox(
          width: size + offset,
          height: size + offset,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: offset,
                top: offset,
                child: Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    color: NuvoColors.inkNavy,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: NuvoColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: NuvoColors.inkNavy, width: 2),
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
                            color: NuvoColors.actionBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
