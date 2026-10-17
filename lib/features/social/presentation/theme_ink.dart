import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Foreground (text / icon) variants of the brand and semantic hues.
///
/// Light mode resolves to the exact same colours as `NuvoColors.blue`,
/// `.success` and `.danger`; dark mode resolves to the lifted `bright`
/// variants so small text and icons keep readable contrast on dark surfaces.
extension NuvoThemeInk on BuildContext {
  Color get blueInk => semanticColors.neutral.bright;
  Color get successInk => semanticColors.success.bright;
  Color get dangerInk => semanticColors.danger.bright;
}

extension NuvoTintX on BuildContext {
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;

  /// Tinted pill/badge fill for a semantic colour: the light-mode alpha is
  /// unchanged, dark mode deepens it so the tint reads on a dark surface.
  Color tintOf(Color c, {double light = 0.12, double dark = 0.22}) =>
      c.withValues(alpha: isDarkTheme ? dark : light);

  /// Text / icon colour for a semantic hue sitting on [tintOf]. Light mode
  /// is the hue itself; dark mode lifts it toward white for contrast.
  Color onTintOf(Color c) =>
      isDarkTheme ? Color.lerp(c, Colors.white, 0.45)! : c;
}
