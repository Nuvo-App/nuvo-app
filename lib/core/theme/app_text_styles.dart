import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography — Space Grotesk for display, Plus Jakarta Sans for body UI.
/// Tight letter-spacing on display sizes for a premium, modern feel.
abstract final class AppTextStyles {
  static TextStyle _body(
    double size,
    FontWeight weight, {
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textPrimary,
        height: height ?? 1.42,
        letterSpacing: letterSpacing ?? 0,
      );

  static TextStyle _display(
    double size,
    FontWeight weight, {
    Color? color,
    double? height,
    double letterSpacing = -0.3,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textPrimary,
        height: height ?? 1.04,
        letterSpacing: letterSpacing,
      );

  // ── Display ───────────────────────────────────────────────────────────────────
  static TextStyle get displayLarge =>
      _display(56, FontWeight.w700, height: 0.98, letterSpacing: -0.5);

  static TextStyle get displayMedium =>
      _display(40, FontWeight.w700, height: 1.00, letterSpacing: -0.4);

  static TextStyle get displaySmall =>
      _display(30, FontWeight.w700, height: 1.06, letterSpacing: -0.3);

  // ── Headline ──────────────────────────────────────────────────────────────────
  static TextStyle get headlineLarge =>
      _display(28, FontWeight.w700, height: 1.10, letterSpacing: -0.3);

  static TextStyle get headlineMedium =>
      _display(22, FontWeight.w700, height: 1.16, letterSpacing: -0.2);

  // ── Title ─────────────────────────────────────────────────────────────────────
  static TextStyle get titleLarge =>
      _body(18, FontWeight.w700, height: 1.26);

  static TextStyle get titleMedium =>
      _body(15, FontWeight.w600, height: 1.32);

  // ── Body ──────────────────────────────────────────────────────────────────────
  static TextStyle get bodyLarge =>
      _body(16, FontWeight.w500, height: 1.55);

  static TextStyle get bodyMedium =>
      _body(14, FontWeight.w500, height: 1.5);

  static TextStyle get bodySmall =>
      _body(12, FontWeight.w500, color: AppColors.textSecondary, height: 1.4);

  // ── Label ─────────────────────────────────────────────────────────────────────
  static TextStyle get labelLarge =>
      _body(14, FontWeight.w700, height: 1.20);

  static TextStyle get labelMedium =>
      _body(12, FontWeight.w700, height: 1.22);

  static TextStyle get labelSmall =>
      _body(10, FontWeight.w600, color: AppColors.textMuted, height: 1.2);

  // ── Brand ─────────────────────────────────────────────────────────────────────
  static TextStyle get brandLabel =>
      _display(13, FontWeight.w700, color: NuvoColors.blue, height: 1.0);
}
