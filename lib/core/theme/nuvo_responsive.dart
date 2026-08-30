import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Responsive sizing for Nuvo.
///
/// The app was authored against a ~390 px logical-width phone with fixed pixel
/// sizes everywhere, so it crowds on a 320 px device and floats on a large
/// phone / tablet. [NuvoResponsive] derives a single clamped scale factor from
/// the viewport's shortest side and exposes helpers to scale sizes, spacing and
/// text against it.
///
/// Usage:
/// ```dart
/// height: context.rs(56),          // scaled pixel size
/// padding: context.rsInsets(const EdgeInsets.all(16)),
/// style: AppTextStyles.titleLarge.scaled(context),
/// ```
class NuvoResponsive {
  const NuvoResponsive._();

  /// Logical width the fixed sizes in the codebase were designed for.
  static const double baselineWidth = 390;

  /// Never shrink below this / grow above this. Keeps small phones legible and
  /// stops tablets from turning into a wall of huge controls.
  static const double minFactor = 0.90;
  static const double maxFactor = 1.18;

  /// Accessibility text scaling is honoured but clamped so fixed-height
  /// controls and single-line labels survive the largest OS setting.
  static const double maxTextScale = 1.30;
  static const double minTextScale = 0.85;

  /// Width-only layout factor (ignores OS text scaling).
  static double factorOf(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortest = math.min(size.width, size.height);
    return (shortest / baselineWidth).clamp(minFactor, maxFactor);
  }
}

extension NuvoResponsiveX on BuildContext {
  /// Clamped width-based layout factor for this context.
  double get nuvoScale => NuvoResponsive.factorOf(this);

  /// Scale a fixed pixel [value] by the layout factor.
  double rs(double value) => value * nuvoScale;

  /// Scale an [EdgeInsets] by the layout factor.
  EdgeInsets rsInsets(EdgeInsets insets) => insets * nuvoScale;

  /// Shortest-side buckets for coarse layout decisions.
  bool get isCompactWidth => MediaQuery.sizeOf(this).width < 360;
  bool get isLargeWidth => MediaQuery.sizeOf(this).width >= 600;
}

extension NuvoTextStyleScaleX on TextStyle {
  /// Return this style with its [fontSize] scaled by the layout factor. Text
  /// still scales again for accessibility via the app's clamped [TextScaler];
  /// this only tracks device size.
  TextStyle scaled(BuildContext context) {
    final size = fontSize;
    if (size == null) return this;
    return copyWith(fontSize: size * context.nuvoScale);
  }
}

/// Wraps [child] in a [MediaQuery] whose [TextScaler] is the app-wide clamped
/// value. Place once, high in the tree (below the root MediaQuery).
class NuvoTextScaleScope extends StatelessWidget {
  const NuvoTextScaleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: NuvoResponsive.minTextScale,
      maxScaleFactor: NuvoResponsive.maxTextScale,
      child: child,
    );
  }
}
