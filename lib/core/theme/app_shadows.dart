import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  static const Color _navyShadow = Color(0xFF07152B);

  // Broad, soft elevation for signature objects such as the race track.
  static const List<BoxShadow> heroShadow = [
    BoxShadow(
      color: Color(0x2407152B),
      blurRadius: 24,
      spreadRadius: -6,
      offset: Offset(0, 14),
    ),
  ];

  // Compact physical offset for primary controls only.
  static const List<BoxShadow> actionShadow = [
    BoxShadow(color: _navyShadow, blurRadius: 0, offset: Offset(0, 4)),
  ];

  // Lower, wider lift for the global navigation dock.
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

  // Restrained treatment for selected or urgent race strips.
  static const List<BoxShadow> selectedShadow = [
    BoxShadow(color: Color(0x3307152B), blurRadius: 0, offset: Offset(0, 3)),
  ];

  // Standard quiet elevation for legacy components that still expect a card.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0D07152B), blurRadius: 14, offset: Offset(0, 6)),
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
