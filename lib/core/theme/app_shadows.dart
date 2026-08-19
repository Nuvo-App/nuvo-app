import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  static const Color _hardColor = NuvoColors.navy;

  /// Solid offset shadow for compact controls.
  static const List<BoxShadow> hardSmall = [
    BoxShadow(color: _hardColor, blurRadius: 0, offset: Offset(3, 3)),
  ];

  /// Solid offset shadow for branded hero/action accents.
  static const List<BoxShadow> hardMedium = [
    BoxShadow(color: _hardColor, blurRadius: 0, offset: Offset(5, 5)),
  ];

  /// Maximum solid offset shadow for rare oversized hero surfaces.
  static const List<BoxShadow> hardLarge = [
    BoxShadow(color: _hardColor, blurRadius: 0, offset: Offset(7, 7)),
  ];

  /// Orange-accent hard offset shadow for CTA emphasis. Matches the
  /// marketing site's orange-shadow chips/CTAs. Use sparingly — only on
  /// primary action surfaces where orange is the accent color.
  static const List<BoxShadow> hardMediumOrange = [
    BoxShadow(color: NuvoColors.orange, blurRadius: 0, offset: Offset(5, 5)),
  ];

  static const List<BoxShadow> hardLargeOrange = [
    BoxShadow(color: NuvoColors.orange, blurRadius: 0, offset: Offset(7, 7)),
  ];

  /// Rare ambient separation for sheets/dialogs where hard offset is too loud.
  static const List<BoxShadow> softSubtle = [
    BoxShadow(
      color: Color(0x1407152D),
      blurRadius: 18,
      spreadRadius: -10,
      offset: Offset(0, 8),
    ),
  ];

  /// Branded lift for premium floating surfaces.
  static const List<BoxShadow> surfaceShadow = hardLarge;

  /// Legacy compact lift for rows, chips, and controls.
  static const List<BoxShadow> hardShadow3 = hardSmall;

  /// Legacy standard lift; ordinary cards and rows stay clean by default.
  static const List<BoxShadow> hardShadow4 = hardMedium;

  /// Legacy hero lift, reduced to the calibrated branded shadow.
  static const List<BoxShadow> hardShadow5 = hardLarge;

  // Primary interactive elevation (buttons, action cards).
  static const List<BoxShadow> actionShadow = hardShadow4;

  // Hero surfaces (focus board, race hero).
  static const List<BoxShadow> heroShadow = hardShadow5;

  // Selected / urgent strips.
  static const List<BoxShadow> selectedShadow = hardShadow3;

  // Default card elevation.
  static const List<BoxShadow> card = hardShadow4;

  // Lower lift for the global navigation dock.
  static const List<BoxShadow> dockShadow = softSubtle;

  static const List<BoxShadow> sheetShadow = softSubtle;

  // Soft blue glow for focused/active elements
  static List<BoxShadow> brandGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.10 * intensity),
      blurRadius: 14 * intensity,
      offset: const Offset(0, 4),
    ),
  ];

  // Mint glow for success / verified states
  static List<BoxShadow> victoryGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.mint.withValues(alpha: 0.12 * intensity),
      blurRadius: 14 * intensity,
      offset: const Offset(0, 4),
    ),
  ];

  // Warm glow (kept for legacy compat, no longer used in new UI)
  static List<BoxShadow> hotGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.warning.withValues(alpha: 0.10 * intensity),
      blurRadius: 12 * intensity,
      offset: const Offset(0, 3),
    ),
  ];
}
