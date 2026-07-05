import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography — Manrope, one family throughout, weight and size doing all
/// the differentiation. Tight letter-spacing on headlines only.
abstract final class AppTextStyles {
  static TextStyle _manrope(
    double size,
    FontWeight weight, {
    Color? color,
    double? height,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textPrimary,
        height: height ?? 1.42,
        letterSpacing: letterSpacing,
      );

  // ── Display ───────────────────────────────────────────────────────────────────
  static TextStyle get displayLarge =>
      _manrope(56, FontWeight.w800, height: 0.98, letterSpacing: -1.1);

  static TextStyle get displayMedium =>
      _manrope(40, FontWeight.w800, height: 1.00, letterSpacing: -0.8);

  static TextStyle get displaySmall =>
      _manrope(30, FontWeight.w800, height: 1.06, letterSpacing: -0.6);

  // ── Headline — screen titles, 26-32, weight 800, ~-0.02em ────────────────────
  static TextStyle get headlineLarge =>
      _manrope(28, FontWeight.w800, height: 1.10, letterSpacing: -0.56);

  static TextStyle get headlineMedium =>
      _manrope(22, FontWeight.w800, height: 1.16, letterSpacing: -0.44);

  // ── Title — card titles / section headers, weight 800, ~17 ──────────────────
  static TextStyle get titleLarge =>
      _manrope(18, FontWeight.w800, height: 1.26, letterSpacing: -0.18);

  static TextStyle get titleMedium =>
      _manrope(17, FontWeight.w800, height: 1.24, letterSpacing: -0.17);

  // ── Body / labels — weight 500-600 ───────────────────────────────────────────
  static TextStyle get bodyLarge => _manrope(16, FontWeight.w500, height: 1.55);

  static TextStyle get bodyMedium => _manrope(14, FontWeight.w500, height: 1.5);

  static TextStyle get bodySmall =>
      _manrope(12, FontWeight.w500, color: AppColors.textSecondary, height: 1.4);

  // ── Label ─────────────────────────────────────────────────────────────────────
  static TextStyle get labelLarge => _manrope(14, FontWeight.w600, height: 1.20);

  static TextStyle get labelMedium => _manrope(12, FontWeight.w600, height: 1.22);

  static TextStyle get labelSmall =>
      _manrope(10, FontWeight.w600, color: AppColors.textMuted, height: 1.2);

  // ── Numbers — scores, stats, counts, weight 600-700, tabular ─────────────────
  static TextStyle number(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w700,
  }) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textPrimary,
        height: 1.0,
        letterSpacing: -0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // ── Brand ─────────────────────────────────────────────────────────────────────
  static TextStyle get brandLabel =>
      _manrope(13, FontWeight.w800, color: NuvoColors.blue, height: 1.0);
}
