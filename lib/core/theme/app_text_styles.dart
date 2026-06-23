import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography — Inter only, athletic scale with tight tracking on display sizes.
abstract final class AppTextStyles {
  static TextStyle _inter(
    double size,
    FontWeight weight, {
    Color? color,
    double? height,
    double? letterSpacing,
  }) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.textPrimary,
    height: height ?? 1.4,
    letterSpacing: letterSpacing ?? 0,
  );

  // ── Display — for big performance numbers (rank, %, totals) ──────────────────
  /// 60px — for oversized stats: rank, percentage complete
  static TextStyle get displayLarge =>
      _inter(60, FontWeight.w900, height: 0.92, letterSpacing: -2.5);

  /// 44px — for prominent stats panels
  static TextStyle get displayMedium =>
      _inter(44, FontWeight.w900, height: 0.96, letterSpacing: -1.8);

  /// 32px — for secondary stats, result screens
  static TextStyle get displaySmall =>
      _inter(32, FontWeight.w800, height: 1.02, letterSpacing: -1.0);

  // ── Headline ─────────────────────────────────────────────────────────────────
  /// 26px — screen titles, race names
  static TextStyle get headlineLarge =>
      _inter(26, FontWeight.w800, height: 1.12, letterSpacing: -0.5);

  /// 21px — section headers, card titles
  static TextStyle get headlineMedium =>
      _inter(21, FontWeight.w700, height: 1.18, letterSpacing: -0.3);

  // ── Title ────────────────────────────────────────────────────────────────────
  static TextStyle get titleLarge  => _inter(17, FontWeight.w700, letterSpacing: -0.1);
  static TextStyle get titleMedium => _inter(15, FontWeight.w700);

  // ── Body ─────────────────────────────────────────────────────────────────────
  static TextStyle get bodyLarge  => _inter(16, FontWeight.w500);
  static TextStyle get bodyMedium => _inter(14, FontWeight.w500);
  static TextStyle get bodySmall  =>
      _inter(12, FontWeight.w500, color: AppColors.textSecondary);

  // ── Label ────────────────────────────────────────────────────────────────────
  static TextStyle get labelLarge  => _inter(14, FontWeight.w800);
  static TextStyle get labelMedium => _inter(12, FontWeight.w700);
  static TextStyle get labelSmall  =>
      _inter(10, FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.4);

  // ── Brand / track label ───────────────────────────────────────────────────────
  /// All-caps track label — ARENA, RACES, MOVE etc.
  static TextStyle get brandLabel =>
      _inter(11, FontWeight.w800, letterSpacing: 1.2);
}
