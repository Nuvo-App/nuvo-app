import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography — Manrope throughout, with bold editorial display styles and
/// compact labels that match Nuvo's sport identity.
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
      _manrope(48, FontWeight.w900, height: 1.02);

  static TextStyle get displayMedium =>
      _manrope(40, FontWeight.w800, height: 1.04);

  static TextStyle get displaySmall =>
      _manrope(34, FontWeight.w800, height: 1.08);

  // ── Headline ────────────────────────────────────────────────────────────────
  static TextStyle get headlineLarge =>
      _manrope(31, FontWeight.w800, height: 1.10);

  /// Screen title — primary top-of-screen title at the 32 px TrackSide scale.
  static TextStyle get screenTitle =>
      _manrope(32, FontWeight.w800, height: 1.10, letterSpacing: -0.9);

  static TextStyle get headlineMedium =>
      _manrope(24, FontWeight.w800, height: 1.15);

  // ── Title ───────────────────────────────────────────────────────────────────
  static TextStyle get titleLarge =>
      _manrope(21, FontWeight.w800, height: 1.22);

  static TextStyle get titleMedium =>
      _manrope(17, FontWeight.w700, height: 1.28);

  // ── Body ────────────────────────────────────────────────────────────────────
  static TextStyle get bodyLarge => _manrope(17, FontWeight.w500, height: 1.5);

  static TextStyle get bodyMedium =>
      _manrope(15, FontWeight.w500, height: 1.45);

  static TextStyle get bodySmall => _manrope(
    13,
    FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // ── Label — small, all-caps ready, high weight ────────────────────────────────
  static TextStyle get labelLarge =>
      _manrope(15, FontWeight.w800, height: 1.15);

  static TextStyle get labelMedium =>
      _manrope(13, FontWeight.w800, height: 1.2);

  static TextStyle get labelSmall =>
      _manrope(11, FontWeight.w700, color: AppColors.textMuted, height: 1.2);

  static TextStyle get buttonLabel =>
      _manrope(15, FontWeight.w900, height: 1.05);

  static TextStyle get statusLabel =>
      _manrope(12, FontWeight.w800, color: AppColors.textMuted, height: 1.1);

  static TextStyle get supportingCopy => bodyMedium.copyWith(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w500,
  );

  /// Tiny timestamp / meta label — use only when the value is already
  /// well-scaled by the calling surface.
  static TextStyle get timestamp =>
      _manrope(10, FontWeight.w600, color: AppColors.textMuted, height: 1.2);

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
    FontWeight.w800,
    color: color ?? AppColors.textMuted,
    letterSpacing: 0.8,
  );

  static TextStyle get eyebrow =>
      labelUppercase(12, color: AppColors.textMuted);

  // ── Brand ─────────────────────────────────────────────────────────────────────
  static TextStyle get brandLabel =>
      _manrope(13, FontWeight.w900, color: NuvoColors.blue, height: 1.0);
}
