import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography — Manrope throughout, with restrained weight and generous
/// leading for a polished, readable hierarchy.
abstract final class AppTextStyles {
  static TextStyle _manrope(
    double size,
    FontWeight weight, {
    Color? color,
    double? height,
    double letterSpacing = 0,
  }) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.textPrimary,
    height: height ?? 1.45,
    letterSpacing: letterSpacing,
  );

  // ── Display ─────────────────────────────────────────────────────────────────
  static TextStyle get displayLarge =>
      _manrope(56, FontWeight.w700, height: 0.98, letterSpacing: -1.6);

  static TextStyle get displayMedium =>
      _manrope(44, FontWeight.w700, height: 1.0, letterSpacing: -1.2);

  static TextStyle get displaySmall =>
      _manrope(34, FontWeight.w700, height: 1.04, letterSpacing: -0.9);

  // ── Headline ────────────────────────────────────────────────────────────────
  static TextStyle get headlineLarge =>
      _manrope(30, FontWeight.w700, height: 1.12, letterSpacing: -0.65);

  static TextStyle get headlineMedium =>
      _manrope(24, FontWeight.w700, height: 1.16, letterSpacing: -0.5);

  // ── Title ───────────────────────────────────────────────────────────────────
  static TextStyle get titleLarge =>
      _manrope(20, FontWeight.w700, height: 1.25, letterSpacing: -0.25);

  static TextStyle get titleMedium =>
      _manrope(17, FontWeight.w600, height: 1.3, letterSpacing: -0.15);

  // ── Body ────────────────────────────────────────────────────────────────────
  static TextStyle get bodyLarge => _manrope(16, FontWeight.w400, height: 1.55);

  static TextStyle get bodyMedium => _manrope(15, FontWeight.w400, height: 1.5);

  static TextStyle get bodySmall => _manrope(
    13,
    FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // ── Label — small, all-caps ready, high weight ────────────────────────────────
  static TextStyle get labelLarge =>
      _manrope(14, FontWeight.w600, height: 1.25);

  static TextStyle get labelMedium =>
      _manrope(12, FontWeight.w600, height: 1.25);

  static TextStyle get labelSmall =>
      _manrope(11, FontWeight.w600, color: AppColors.textMuted, height: 1.25);

  // ── Numbers — scores, stats, counts, tabular figures ──────────────────────────
  static TextStyle number(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w600,
  }) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.textPrimary,
    height: 1.0,
    letterSpacing: -0.3,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Uppercase label helper. Use for movement tags, status, and section kicker.
  static TextStyle labelUppercase(double size, {Color? color}) => _manrope(
    size,
    FontWeight.w700,
    color: color ?? AppColors.textMuted,
    letterSpacing: 0.8,
  );

  // ── Brand ─────────────────────────────────────────────────────────────────────
  static TextStyle get brandLabel =>
      _manrope(13, FontWeight.w700, color: NuvoColors.blue, height: 1.0);
}
