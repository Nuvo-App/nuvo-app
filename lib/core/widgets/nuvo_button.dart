import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../theme/nuvo_responsive.dart';
import 'nuvo_motion.dart';
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
  required BuildContext context,
  required String label,
  required Color textColor,
  IconData? icon,
  Widget? leadingWidget,
  bool loading = false,
  bool animatedLabel = false,
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

  // A button label must never truncate to "Submit…". When the button is
  // narrower than the label, shrink the text to fit instead of clipping it.
  Widget labelText = Text(
    label,
    key: ValueKey(label),
    maxLines: 1,
    softWrap: false,
    style: AppTextStyles.buttonLabel.copyWith(color: textColor),
  );
  if (animatedLabel && !MediaQuery.disableAnimationsOf(context)) {
    // Labels that react to user choices (e.g. "Continue with Plank") swap
    // with a short crossfade — the button chrome itself stays put.
    labelText = AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: labelText,
    );
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (leadingWidget != null) ...[leadingWidget, const SizedBox(width: 8)],
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: labelText,
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
  double horizontalPadding = 24,
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
    horizontalPadding: horizontalPadding,
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
    this.horizontalPadding = 24,
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
  final double horizontalPadding;

  @override
  State<_PhysicalButtonShell> createState() => _PhysicalButtonShellState();
}

class _PhysicalButtonShellState extends State<_PhysicalButtonShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.pressIn,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _press(double target) {
    if (!widget.enabled || widget.onTap == null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = target;
      return;
    }
    if (target == 0) {
      // Spring release: easeOutBack dips just past rest so the button pops
      // off its shadow instead of gliding back.
      _ctrl.animateTo(
        0,
        duration: NuvoMotion.pressOut,
        curve: NuvoMotion.spring,
      );
    } else {
      _ctrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: (_) => _press(1),
      onTapCancel: () => _press(0),
      onTapUp: (_) => _press(0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: widget.enabled ? 1 : 0.58,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _ctrl.value;
            // The face travels toward its shadow while the shadow keeps a
            // compressed residual (5px → 2px) — "pressed through", not
            // "shadow deleted".
            final travel = NuvoMotion.buttonPressDepth * t;
            final shadowKeep = 1 - NuvoMotion.shadowCompress * t;
            return Container(
              transform: Matrix4.translationValues(travel, travel, 0),
              width: widget.expand ? double.infinity : null,
              height: widget.height,
              padding: EdgeInsets.symmetric(
                horizontal: widget.horizontalPadding,
              ),
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
                boxShadow: widget.shadows
                    ?.map(
                      (s) => s.copyWith(offset: s.offset * shadowKeep),
                    )
                    .toList(),
              ),
              child: child,
            );
          },
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
    this.horizontalPadding,
    this.animatedLabel = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leadingWidget;
  final bool expand;
  final bool loading;
  final bool small;

  /// Crossfades the label text when it changes (e.g. a CTA that reacts to a
  /// choice) without touching the button chrome. Off by default so static
  /// labels pay nothing.
  final bool animatedLabel;

  /// Overrides the default 46/56 height for a screen that needs its own
  /// emphasis (e.g. a chunkier hero action row) without changing every
  /// other caller's default.
  final double? height;

  /// Overrides the default 24px internal horizontal padding. Use a smaller
  /// value for a button that must sit in a narrow flex column (e.g. a
  /// secondary action in a multi-button row) so icon + label have real room
  /// instead of both being squeezed by a padding sized for a full-width
  /// button.
  final double? horizontalPadding;

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
    final c = context.themeColors;
    final enabled = onPressed != null && !loading;
    final List<BoxShadow>? shadows;
    if (!enabled) {
      shadows = null;
    } else if (flat || subtleLift) {
      shadows = AppShadows.hardOffset(c.inkShadow);
    } else {
      shadows = AppShadows.hardOffset(
        c.inkShadow,
        offset: const Offset(5, 5),
      );
    }
    return _buttonShell(
      context: context,
      height: height ?? (small ? 46 : 56),
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: enabled ? NuvoColors.actionBlue : c.panel,
      borderColor: c.border,
      shadows: shadows,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      horizontalPadding: horizontalPadding ?? 24,
      child: _buttonContent(
        context: context,
        label: label,
        textColor: enabled ? NuvoColors.white : c.inkDim,
        icon: icon,
        leadingWidget: leadingWidget,
        loading: loading,
        animatedLabel: animatedLabel,
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
    this.horizontalPadding,
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

  /// Overrides the default 24px internal horizontal padding — see
  /// [NuvoPrimaryButton.horizontalPadding].
  final double? horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final enabled = onPressed != null;
    return _buttonShell(
      context: context,
      height: height ?? (small ? 46 : 56),
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: c.surface,
      borderColor: c.border,
      shadows: enabled ? AppShadows.hardOffset(c.inkShadow) : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      horizontalPadding: horizontalPadding ?? 24,
      child: iconOnly
          ? Semantics(
              label: label.isEmpty ? null : label,
              button: true,
              child: Center(
                child: icon == null
                    ? leadingWidget
                    : Icon(icon, color: c.ink, size: 22),
              ),
            )
          : _buttonContent(
              context: context,
              label: label,
              textColor: c.ink,
              icon: icon,
              leadingWidget: leadingWidget,
            ),
    );
  }
}

typedef NuvoSecondaryButton = NuvoOutlineButton;

// ── Copy — a secondary-tier control whose surface confirms itself ──────────

/// A copy action that answers locally: press → the link icon pops into a
/// check, the label becomes [copiedLabel], a confirm haptic lands, and the
/// control resets itself after ~2.5s. No SnackBar — the surface is the
/// response (docs/ui/NUVO_PLAY_SYSTEM.md §13.2).
///
/// Outline-tier chrome so it swaps in wherever a `NuvoSecondaryButton`
/// copy action lived. Errors stay global: if [onCopy] throws, callers
/// decide whether to surface it — this control never claims success.
class NuvoCopyButton extends StatefulWidget {
  const NuvoCopyButton({
    super.key,
    required this.text,
    this.label = 'Copy link',
    this.copiedLabel = 'Copied',
    this.icon = Icons.link_rounded,
    this.expand = false,
    this.small = false,
    this.height,
    this.enabled = true,
  });

  /// What lands on the clipboard on tap.
  final String text;
  final String label;
  final String copiedLabel;
  final IconData icon;
  final bool expand;
  final bool small;
  final double? height;
  final bool enabled;

  @override
  State<NuvoCopyButton> createState() => _NuvoCopyButtonState();
}

class _NuvoCopyButtonState extends State<NuvoCopyButton> {
  bool _copied = false;
  Timer? _reset;

  Future<void> _copy() async {
    if (_copied) return; // a second tap during the reset is a no-op
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    NuvoHaptics.confirm();
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final success = context.semanticColors.success;
    final enabled = widget.enabled && widget.text.isNotEmpty;
    final copied = _copied;
    return _buttonShell(
      context: context,
      height: widget.height ?? (widget.small ? 46 : 56),
      radius: widget.small ? NuvoRadii.md : NuvoRadii.button,
      color: copied ? success.surface : c.surface,
      borderColor: copied ? success.border : c.border,
      shadows: enabled ? AppShadows.hardOffset(c.inkShadow) : null,
      onTap: enabled ? _copy : null,
      enabled: enabled,
      expand: widget.expand,
      child: AnimatedSwitcher(
        duration: NuvoMotion.select,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: KeyedSubtree(
          key: ValueKey(copied),
          child: _buttonContent(
            context: context,
            label: copied ? widget.copiedLabel : widget.label,
            textColor: copied ? success.on : c.ink,
            icon: copied ? Icons.check_rounded : widget.icon,
          ),
        ),
      ),
    );
  }
}


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
    this.height,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leadingWidget;
  final bool expand;
  final bool small;

  /// Overrides the default 44/52 height — see [NuvoPrimaryButton.height].
  final double? height;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final enabled = onPressed != null;
    return _buttonShell(
      context: context,
      height: height ?? (small ? 44 : 52),
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: c.panel,
      borderColor: c.divider,
      // 2d: outline only, no drop shadow (kept for API compatibility — the
      // shell's 3px default still applies).
      shadows: null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        context: context,
        label: label,
        textColor: c.ink,
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
    super.height,
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
    final role = context.semanticColors.success;
    final enabled = onPressed != null && !loading;
    return _buttonShell(
      context: context,
      height: small ? 46 : 54,
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: solid ? role.base : role.surface,
      borderColor: solid ? role.shadow : role.border,
      shadows: enabled ? _tinted(role.shadow) : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        context: context,
        label: label,
        textColor: solid ? NuvoColors.white : role.on,
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
    final role = context.semanticColors.danger;
    final enabled = onPressed != null && !loading;
    return _buttonShell(
      context: context,
      height: small ? 44 : 54,
      radius: small ? NuvoRadii.md : NuvoRadii.button,
      color: solid ? role.base : role.surface,
      borderColor: solid ? role.shadow : role.border,
      shadows: enabled ? _tinted(role.shadow) : null,
      onTap: onPressed,
      enabled: enabled,
      expand: expand,
      child: _buttonContent(
        context: context,
        label: label,
        textColor: solid ? NuvoColors.white : role.on,
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
    final c = context.themeColors;
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
            color: c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: c.border, width: 2),
            boxShadow: AppShadows.hardOffset(c.inkShadow),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            color: c.ink,
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
    this.iconColor,
    this.badge = false,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool badge;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
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
            color: c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: c.border, width: 1.5),
            boxShadow: AppShadows.hardOffset(c.inkShadow),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: iconColor ?? c.ink, size: 19),
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
                      border: Border.all(color: c.surface, width: 1.2),
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
