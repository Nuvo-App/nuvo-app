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

  // ── Display — huge stats, tight leading, aggressive tracking ────────────────
  static TextStyle get displayLarge =>
      _manrope(64, FontWeight.w800, height: 0.92, letterSpacing: -2);

  static TextStyle get displayMedium =>
      _manrope(48, FontWeight.w800, height: 0.96, letterSpacing: -1.5);

  static TextStyle get displaySmall =>
      _manrope(36, FontWeight.w800, height: 1.0, letterSpacing: -1);

  // ── Headline — screen titles, weight 800, tight ─────────────────────────────
  static TextStyle get headlineLarge =>
      _manrope(32, FontWeight.w800, height: 1.05, letterSpacing: -0.8);

  static TextStyle get headlineMedium =>
      _manrope(26, FontWeight.w800, height: 1.08, letterSpacing: -0.65);

  // ── Title — object titles, weight 800 ─────────────────────────────────────────
  static TextStyle get titleLarge =>
      _manrope(20, FontWeight.w800, height: 1.18, letterSpacing: -0.3);

  static TextStyle get titleMedium =>
      _manrope(18, FontWeight.w800, height: 1.22, letterSpacing: -0.25);

  // ── Body — weight 500-600, comfortable reading ────────────────────────────────
  static TextStyle get bodyLarge => _manrope(16, FontWeight.w500, height: 1.5);

  static TextStyle get bodyMedium => _manrope(15, FontWeight.w500, height: 1.5);

  static TextStyle get bodySmall =>
      _manrope(13, FontWeight.w500, color: AppColors.textSecondary, height: 1.4);

  // ── Label — small, all-caps ready, high weight ────────────────────────────────
  static TextStyle get labelLarge => _manrope(14, FontWeight.w700, height: 1.18);

  static TextStyle get labelMedium => _manrope(12, FontWeight.w700, height: 1.2);

  static TextStyle get labelSmall =>
      _manrope(11, FontWeight.w700, color: AppColors.textMuted, height: 1.2);

  // ── Numbers — scores, stats, counts, tabular figures ──────────────────────────
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
        letterSpacing: -0.3,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Uppercase label helper. Use for movement tags, status, and section kicker.
  static TextStyle labelUppercase(double size, {Color? color}) =>
      _manrope(
        size,
        FontWeight.w800,
        color: color ?? AppColors.textMuted,
        letterSpacing: 0.8,
      );

  // ── Brand ─────────────────────────────────────────────────────────────────────
  static TextStyle get brandLabel =>
      _manrope(13, FontWeight.w800, color: NuvoColors.blue, height: 1.0);
}
