import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  /// Restrained two-stage elevation for premium floating surfaces.
  ///
  /// Both layers stay neutral so elevation never competes with Nuvo's blue
  /// action color.
  static const List<BoxShadow> surfaceShadow = [
    BoxShadow(
      color: Color(0x1207152C),
      blurRadius: 24,
      spreadRadius: -12,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0F07152C),
      blurRadius: 7,
      spreadRadius: -3,
      offset: Offset(0, 3),
    ),
  ];

  /// Compact lift for rows, chips, and controls.
  static const List<BoxShadow> hardShadow3 = [
    BoxShadow(
      color: Color(0x0F07152C),
      blurRadius: 8,
      spreadRadius: -4,
      offset: Offset(0, 3),
    ),
  ];

  /// Quiet lift for buttons, lanes, and standard cards.
  static const List<BoxShadow> hardShadow4 = [
    BoxShadow(
      color: Color(0x1207152C),
      blurRadius: 13,
      spreadRadius: -6,
      offset: Offset(0, 6),
    ),
  ];

  /// Soft depth for hero and focus surfaces.
  static const List<BoxShadow> hardShadow5 = [
    BoxShadow(
      color: Color(0x1407152C),
      blurRadius: 20,
      spreadRadius: -9,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x0D07152C),
      blurRadius: 6,
      spreadRadius: -3,
      offset: Offset(0, 3),
    ),
  ];

  // Compatibility names used by screens introduced on the remote branch.
  static const List<BoxShadow> hardSmall = hardShadow3;
  static const List<BoxShadow> hardMedium = hardShadow4;
  static const List<BoxShadow> hardLarge = hardShadow5;

  // Primary interactive elevation (buttons, action cards).
  static const List<BoxShadow> actionShadow = hardShadow4;

  // Hero surfaces (focus board, race hero).
  static const List<BoxShadow> heroShadow = hardShadow5;

  // Selected / urgent strips.
  static const List<BoxShadow> selectedShadow = hardShadow3;

  // Default card elevation.
  static const List<BoxShadow> card = hardShadow4;

  // The global navigation dock uses the same neutral elevation language.
  static const List<BoxShadow> dockShadow = surfaceShadow;

  static const List<BoxShadow> sheetShadow = [
    BoxShadow(
      color: Color(0x1407152C),
      blurRadius: 28,
      spreadRadius: -10,
      offset: Offset(0, -6),
    ),
  ];

  // Quiet brand emphasis reserved for focused/active elements.
  static List<BoxShadow> brandGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.07 * intensity),
      blurRadius: 12 * intensity,
      offset: const Offset(0, 3),
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
