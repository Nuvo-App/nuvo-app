import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  /// Layered blue-and-navy depth for premium floating surfaces.
  static const List<BoxShadow> surfaceShadow = [
    BoxShadow(
      color: Color(0x140165FC),
      blurRadius: 30,
      spreadRadius: -16,
      offset: Offset(0, 16),
    ),
    BoxShadow(
      color: Color(0x1007152C),
      blurRadius: 16,
      spreadRadius: -9,
      offset: Offset(0, 7),
    ),
  ];

  /// Compact lift for rows, chips, and controls.
  static const List<BoxShadow> hardShadow3 = [
    BoxShadow(
      color: Color(0x1207152C),
      blurRadius: 10,
      spreadRadius: -4,
      offset: Offset(0, 3),
    ),
  ];

  /// Quiet lift for buttons, lanes, and standard cards.
  static const List<BoxShadow> hardShadow4 = [
    BoxShadow(
      color: Color(0x1407152C),
      blurRadius: 14,
      spreadRadius: -5,
      offset: Offset(0, 5),
    ),
  ];

  /// Soft depth for hero and focus surfaces.
  static const List<BoxShadow> hardShadow5 = [
    BoxShadow(
      color: Color(0x1607152C),
      blurRadius: 20,
      spreadRadius: -7,
      offset: Offset(0, 8),
    ),
  ];

  // Primary interactive elevation (buttons, action cards).
  static const List<BoxShadow> actionShadow = hardShadow4;

  // Hero surfaces (focus board, race hero).
  static const List<BoxShadow> heroShadow = hardShadow5;

  // Selected / urgent strips.
  static const List<BoxShadow> selectedShadow = hardShadow3;

  // Default card elevation.
  static const List<BoxShadow> card = hardShadow4;

  // Lower, wider lift for the global navigation dock (soft, intentional).
  static const List<BoxShadow> dockShadow = [
    BoxShadow(
      color: Color(0x140165FC),
      blurRadius: 34,
      spreadRadius: -16,
      offset: Offset(0, 16),
    ),
    BoxShadow(
      color: Color(0x1207152C),
      blurRadius: 22,
      spreadRadius: -8,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> sheetShadow = [
    BoxShadow(
      color: Color(0x1407152C),
      blurRadius: 28,
      spreadRadius: -10,
      offset: Offset(0, -6),
    ),
  ];

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
