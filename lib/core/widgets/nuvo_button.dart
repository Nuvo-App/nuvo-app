import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../theme/nuvo_responsive.dart';
import '../theme/nuvo_tokens.dart';
import 'pressable_scale.dart';

/// Nuvo button system.
///
/// Every tier is a *physical* control: a solid fill, a 2 px ink edge, and a
/// hard-offset shadow that the button sinks into when pressed. There are no
/// transparent or flat buttons — use a plain [TextButton]/inline link only for
/// true text affordances (and even those are being converted to chips).
///
/// | Tier                | Fill              | Border  | Shadow      |
/// |---------------------|-------------------|---------|-------------|
/// | `NuvoPrimaryButton` | action blue       | navy    | hardMedium  |
/// | `NuvoSecondaryButton`| surface (white)  | navy    | hardSmall   |
/// | `NuvoTertiaryButton`| gray-100          | gray-300| hardSmall   |
/// | `NuvoSuccessButton` | success surface   | success | hardSmall   |
/// | `NuvoDangerButton`  | danger surface    | danger  | hardSmall   |
///
/// Labels auto-shrink, never truncate: [_buttonContent] wraps the label in a
/// `FittedBox(scaleDown)` so a narrow button scales the text down instead of
/// clipping to "Submit…" (pitfall D2). Don't add `overflow: ellipsis` to a
/// label or restructure a layout to fit one. Height only grows on phones
/// ≥ 430 px wide, capped at 1.10× ([_buttonShell]) so test surfaces keep the
/// designed height. Full cookbook: docs/agents/09-widget-and-token-reference.md.

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
      // A button label must never truncate to "Submit…". When the button is
      // narrower than the label, shrink the text to fit instead of clipping it.
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: AppTextStyles.buttonLabel.copyWith(color: textColor),
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
  required BuildContext context,
  required Widget child,
  required VoidCallback? onTap,
  required bool enabled,
  required double height,
  required double radius,
  required Color color,
  Color? borderColor,
  // Design guide: a "3d"/"2d" button carries a 3px outline in the shadow
  // color of its fill.
  double borderWidth = 3,
  bool expand = false,
  List<BoxShadow>? shadows,
}) {
  // Grow the control height only on genuinely large phones, and only slightly,
  // so small-screen / test viewports keep the designed height exactly.
  final w = MediaQuery.sizeOf(context).width;
  final scale = w >= 430 ? (w / 430).clamp(1.0, 1.10) : 1.0;
  final button = _PhysicalButtonShell(
    onTap: onTap,
    enabled: enabled,
    height: height * scale,
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

// ── Primary ──────────────────────────────────────────────────────────────────

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
    this.flat = false,
    this.subtleLift = false,
    this.height,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leadingWidget;
  final bool expand;
  final bool loading;
  final bool small;

  /// Overrides the default 46/56 height for a screen that needs its own
  /// emphasis (e.g. a chunkier hero action row) without changing every
  /// other caller's default.
  final double? height;

  /// Kept for API compatibility. A flat primary now still carries a shadow —
  /// the lighter [AppShadows.hardSmall] instead of the hero [AppShadows.hardMedium]
  /// — so it reads as tappable on dark or secondary surfaces without competing
  /// with the screen's hero depth.
  final bool flat;

  /// Kept for API compatibility; behaves like [flat] now that no button is
  /// shadowless.
  final bool subtleLift;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final List<BoxShadow>? shadows;
    if (!enabled) {
      shadows = null;
    } else if (flat || subtleLift) {
      shadows = AppShadows.hardSmall;
    } else {
      shadows = AppShadows.hardMedium;
    }
    return _buttonShell(
      context: context,
      height: height ?? (small ? 46 : 56),
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: enabled ? NuvoColors.actionBlue : NuvoColors.disabledSurface,
      borderColor: enabled ? NuvoColors.navy : NuvoColors.border,
      shadows: shadows,
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

// ── Secondary (outline) ──────────────────────────────────────────────────────

class NuvoOutlineButton extends StatelessWidget {
  const NuvoOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leadingWidget,
    this.expand = false,
    this.small = false,
    this.flat = false,
    this.iconOnly = false,
    this.height,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leadingWidget;
  final bool expand;
  final bool small;

  /// Kept for API compatibility — a flat secondary still carries [hardSmall].
  final bool flat;

  /// Centers the icon independently when the control has no visible label.
  final bool iconOnly;

  /// Overrides the default 46/56 height — see [NuvoPrimaryButton.height].
  final double? height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return _buttonShell(
      context: context,
      height: height ?? (small ? 46 : 56),
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: NuvoColors.surface,
      borderColor: enabled ? NuvoColors.navy : NuvoColors.border,
      shadows: enabled ? AppShadows.hardSmall : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: iconOnly
          ? Semantics(
              label: label.isEmpty ? null : label,
              button: true,
              child: Center(
                child: icon == null
                    ? leadingWidget
                    : Icon(icon, color: NuvoColors.navy, size: 22),
              ),
            )
          : _buttonContent(
              label: label,
              textColor: NuvoColors.navy,
              icon: icon,
              leadingWidget: leadingWidget,
            ),
    );
  }
}

typedef NuvoSecondaryButton = NuvoOutlineButton;

// ── Tertiary — the "2d" button: same fill+outline construction as the 3d
// tiers, but no drop shadow. Use for lower-emphasis actions (a settings page,
// a secondary control) where the 3d tiers' physical pop isn't warranted.
// (was Ghost — now a filled low-emphasis tier) ───────────────────────────────

class NuvoTertiaryButton extends StatelessWidget {
  const NuvoTertiaryButton({
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
      context: context,
      height: small ? 44 : 52,
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: NuvoTokens.gray100,
      borderColor: NuvoTokens.gray300,
      // 2d: outline only, no drop shadow (kept for API compatibility — the
      // shell's 3px default still applies).
      shadows: null,
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

/// Legacy name. A ghost button is no longer transparent — it renders as a
/// [NuvoTertiaryButton] (2d: filled gray-100 + outline, no shadow).
class NuvoGhostButton extends NuvoTertiaryButton {
  const NuvoGhostButton({
    super.key,
    required super.label,
    super.onPressed,
    super.icon,
    super.expand,
    super.small,
  });
}

// ── Success ──────────────────────────────────────────────────────────────────

class NuvoSuccessButton extends StatelessWidget {
  const NuvoSuccessButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.small = false,
    this.loading = false,
    this.solid = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool small;
  final bool loading;

  /// When true, fills with the solid success colour and white text (for a
  /// primary confirm), otherwise the calmer tinted surface.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return _buttonShell(
      context: context,
      height: small ? 46 : 54,
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: solid ? NuvoColors.success : NuvoColors.successSurface,
      borderColor: solid ? NuvoColors.successShadow : NuvoColors.success,
      shadows: enabled ? _tinted(NuvoColors.successShadow) : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        label: label,
        textColor: solid ? NuvoColors.white : NuvoColors.successOn,
        icon: icon,
        loading: loading,
      ),
    );
  }
}

/// A hard-offset shadow tinted to a semantic role (a darker shade of the fill),
/// per the Nuvo palette reference.
List<BoxShadow> _tinted(Color shadow) => [
  BoxShadow(color: shadow, blurRadius: 0, offset: const Offset(3, 3)),
];

// ── Danger ───────────────────────────────────────────────────────────────────

class NuvoDangerButton extends StatelessWidget {
  const NuvoDangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.small = false,
    this.loading = false,
    this.solid = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool small;
  final bool loading;

  /// When true, fills solid red with white text (destructive confirm).
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return _buttonShell(
      context: context,
      height: small ? 44 : 54,
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: solid ? NuvoColors.danger : NuvoColors.dangerSurface,
      borderColor: solid ? NuvoColors.dangerShadow : NuvoColors.danger,
      shadows: enabled ? _tinted(NuvoColors.dangerShadow) : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        label: label,
        textColor: solid ? NuvoColors.white : NuvoColors.dangerOn,
        icon: icon,
        loading: loading,
      ),
    );
  }
}

// ── Back / icon actions ──────────────────────────────────────────────────────

class NuvoBackButton extends StatelessWidget {
  const NuvoBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final d = context.rs(46).clamp(44.0, 54.0);
    return Semantics(
      button: true,
      label: 'Back',
      child: PressableScale(
        onTap: onPressed,
        scale: 0.94,
        child: Container(
          width: d,
          height: d,
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
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final bool badge;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final d = context.rs(42).clamp(42.0, 50.0);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: PressableScale(
        onTap: onTap,
        scale: 0.94,
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: NuvoColors.navy, width: 1.5),
            boxShadow: AppShadows.hardSmall,
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
                      color: NuvoColors.dangerBright,
                      shape: BoxShape.circle,
                      border: Border.all(color: NuvoColors.surface, width: 1.2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
