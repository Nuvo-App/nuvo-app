import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Touch feedback for flat controls — surfaces with no offset shadow and no
/// physical press to compress (header icons, toolbar glyphs, ghost actions).
/// The metaphor is a small Nuvo-blue/ice ripple spreading from the touch
/// point, never the default Material gray.
///
/// Hierarchy rule (docs/ui/NUVO_PLAY_SYSTEM.md §13.3): a control uses ripple
/// OR physical depth as its touch metaphor — never both. Signature CTAs keep
/// their shadow press; this is for the lightweight residue (Search, QR,
/// bell) where a physical button would be too loud.
///
/// Reduced motion: the splash is suppressed; a quiet highlight still marks
/// the touch so feedback isn't absent entirely.
class NuvoRippleSurface extends StatelessWidget {
  const NuvoRippleSurface({
    super.key,
    required this.onTap,
    required this.child,
    this.size = 44,
    this.radius,
  });

  final VoidCallback? onTap;
  final Widget child;

  /// The square hit area — 44 keeps every icon control at the touch-target
  /// floor without caller math.
  final double size;

  /// Ink spread. Defaults to just past the hit area so the ripple reads as
  /// contained, not a page-wide splash.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Material(
      type: MaterialType.transparency,
      child: InkResponse(
        onTap: onTap,
        radius: radius ?? (size / 2) + 4,
        highlightShape: BoxShape.circle,
        containedInkWell: false,
        splashColor: reduced
            ? Colors.transparent
            : NuvoColors.actionBlue.withValues(alpha: 0.14),
        highlightColor: NuvoColors.actionBlue.withValues(alpha: 0.07),
        splashFactory: reduced ? NoSplash.splashFactory : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}
