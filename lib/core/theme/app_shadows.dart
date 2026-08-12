import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Premium, consistent elevation system for the Nuvo app.
///
/// All shadows are soft, subtle, and intention-driven:
/// - Blue glow is reserved for interactive/hero emphasis
/// - Navy lift is used for card and surface depth
/// - Legacy hard-offset shadows have been replaced with diffuse, layered shadows
abstract final class AppShadows {
  // ── Branded track-blue glow (interactive and hero emphasis) ─────────────────

  /// Primary CTA / action glow. Strong and focused.
  static const List<BoxShadow> trackBlueGlow = [
    BoxShadow(
      color: Color(0x3F2F7CFF), // trackBlue @ 25%
      blurRadius: 20,
      spreadRadius: -3,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x1A2F7CFF), // trackBlue @ 10%
      blurRadius: 36,
      spreadRadius: -10,
      offset: Offset(0, 10),
    ),
  ];

  /// Subtle track-blue halo for outline and secondary actions.
  static const List<BoxShadow> trackBlueGlowSubtle = [
    BoxShadow(
      color: Color(0x1A2F7CFF), // trackBlue @ 10%
      blurRadius: 14,
      spreadRadius: -2,
      offset: Offset(0, 4),
    ),
  ];

  // ── Navy lift (cards, surfaces, small controls) ─────────────────────────────

  /// Small, focused lift for compact controls and icon buttons.
  static const List<BoxShadow> hardSmall = [
    BoxShadow(
      color: Color(0x1A071B35), // trackNavy @ 10%
      blurRadius: 10,
      spreadRadius: -2,
      offset: Offset(0, 3),
    ),
  ];

  /// Standard lift for list and content cards.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x14071B35), // trackNavy @ 8%
      blurRadius: 24,
      spreadRadius: -8,
      offset: Offset(0, 8),
    ),
  ];

  /// Premium hero surface — layered navy lift + soft blue glow.
  static const List<BoxShadow> heroShadow = [
    BoxShadow(
      color: Color(0x1A071B35), // trackNavy @ 10%
      blurRadius: 28,
      spreadRadius: -8,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x1A2F7CFF), // trackBlue @ 10%
      blurRadius: 40,
      spreadRadius: -12,
      offset: Offset(0, 10),
    ),
  ];

  /// Large floating surfaces, dialogs, sheets.
  static const List<BoxShadow> surfaceShadow = [
    BoxShadow(
      color: Color(0x1F071B35), // trackNavy @ 12%
      blurRadius: 36,
      spreadRadius: -10,
      offset: Offset(0, 16),
    ),
    BoxShadow(
      color: Color(0x0D071B35), // trackNavy @ 5%
      blurRadius: 60,
      spreadRadius: -18,
      offset: Offset(0, 24),
    ),
  ];

  // ── Legacy / named aliases (kept for compatibility, now consistent) ──────────

  static const List<BoxShadow> hardMedium = card;
  static const List<BoxShadow> hardLarge = heroShadow;
  static const List<BoxShadow> hardShadow3 = hardSmall;
  static const List<BoxShadow> hardShadow4 = card;
  static const List<BoxShadow> hardShadow5 = heroShadow;

  /// Primary interactive elevation (buttons, action cards).
  static const List<BoxShadow> actionShadow = trackBlueGlow;

  /// Selected / urgent strips.
  static const List<BoxShadow> selectedShadow = trackBlueGlowSubtle;

  /// Floating navigation pill — soft, wide, upward-biased lift so the bar
  /// reads as hovering above the page without a heavy edge.
  static const List<BoxShadow> navBar = [
    BoxShadow(
      color: Color(0x14152238), // navy @ 8%
      blurRadius: 20,
      spreadRadius: -4,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x0A152238), // navy @ 4%
      blurRadius: 40,
      spreadRadius: -8,
      offset: Offset(0, 12),
    ),
  ];

  /// Lower lift for the global navigation dock.
  static const List<BoxShadow> dockShadow = hardSmall;

  /// Soft ambient separation for sheets and dialogs.
  static const List<BoxShadow> sheetShadow = surfaceShadow;

  // ── State / accent glows ───────────────────────────────────────────────────

  /// Success / verified glow.
  static List<BoxShadow> victoryGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.mint.withValues(alpha: 0.12 * intensity),
      blurRadius: 14 * intensity,
      offset: const Offset(0, 4),
    ),
  ];

  /// Warning / hot glow (legacy compat).
  static List<BoxShadow> hotGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.warning.withValues(alpha: 0.10 * intensity),
      blurRadius: 12 * intensity,
      offset: const Offset(0, 3),
    ),
  ];

  /// Soft, diffuse blue lift for non-hero focus states.
  static List<BoxShadow> brandGlow({double intensity = 1}) => [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.10 * intensity),
      blurRadius: 14 * intensity,
      offset: const Offset(0, 4),
    ),
  ];
}
