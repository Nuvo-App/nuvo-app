import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  static const Color _inkNavy = NuvoColors.inkNavy;

  /// Hard offset 3 — rows, chips, compact controls.
  static const List<BoxShadow> hardShadow3 = [
    BoxShadow(color: _inkNavy, blurRadius: 0, offset: Offset(3, 3)),
  ];

  /// Hard offset 4 — buttons, board lanes, standard cards.
  static const List<BoxShadow> hardShadow4 = [
    BoxShadow(color: _inkNavy, blurRadius: 0, offset: Offset(4, 4)),
  ];

  /// Hard offset 5 — hero / focus surfaces.
  static const List<BoxShadow> hardShadow5 = [
    BoxShadow(color: _inkNavy, blurRadius: 0, offset: Offset(5, 5)),
  ];

  // Primary interactive elevation (buttons, action cards).
  static const List<BoxShadow> actionShadow = hardShadow4;

  // Hero surfaces (focus board, race hero).
  static const List<BoxShadow> heroShadow = hardShadow5;

  // Selected / urgent strips.
  static const List<BoxShadow> selectedShadow = hardShadow3;

  // Default card elevation — hard offset (Phase 0).
  static const List<BoxShadow> card = hardShadow4;

  // Lower, wider lift for the global navigation dock (soft, intentional).
  static const List<BoxShadow> dockShadow = [
    BoxShadow(
      color: Color(0x1A07152B),
      blurRadius: 14,
      spreadRadius: -6,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> sheetShadow = [
    BoxShadow(
      color: Color(0x1F07152B),
      blurRadius: 26,
      spreadRadius: -8,
      offset: Offset(0, -8),
    ),
  ];

  // Soft blue glow for focused/active elements
  static List<BoxShadow> brandGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.18 * intensity),
      blurRadius: 16 * intensity,
      offset: const Offset(0, 4),
    ),
  ];

  // Mint glow for success / verified states
  static List<BoxShadow> victoryGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.mint.withValues(alpha: 0.22 * intensity),
      blurRadius: 16 * intensity,
      offset: const Offset(0, 4),
    ),
  ];

  // Warm glow (kept for legacy compat, no longer used in new UI)
  static List<BoxShadow> hotGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.warning.withValues(alpha: 0.16 * intensity),
      blurRadius: 12 * intensity,
      offset: const Offset(0, 3),
    ),
  ];
}
