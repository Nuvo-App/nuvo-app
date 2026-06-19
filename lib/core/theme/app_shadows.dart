import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  // Standard card elevation on white/light backgrounds
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 1)),
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
