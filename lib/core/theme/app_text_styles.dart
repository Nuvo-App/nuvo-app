import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography — Inter only. Matches the website's modern sans-serif feel.
/// No Orbitron / sci-fi typefaces.
abstract final class AppTextStyles {
  static TextStyle _inter(double size, FontWeight weight,
          {Color? color, double? height, double? letterSpacing}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textPrimary,
        height: height ?? 1.4,
        letterSpacing: letterSpacing,
      );

  // --- Display (hero/splash) -----------------------------------------------
  static TextStyle get displayLarge =>
      _inter(36, FontWeight.w800, height: 1.1);
  static TextStyle get displayMedium =>
      _inter(28, FontWeight.w700, height: 1.15);

  // --- Headings ------------------------------------------------------------
  static TextStyle get headlineLarge => _inter(24, FontWeight.w700);
  static TextStyle get headlineMedium => _inter(20, FontWeight.w600);
  static TextStyle get titleLarge => _inter(17, FontWeight.w600);
  static TextStyle get titleMedium => _inter(15, FontWeight.w600);

  // --- Body ----------------------------------------------------------------
  static TextStyle get bodyLarge => _inter(16, FontWeight.w400);
  static TextStyle get bodyMedium => _inter(14, FontWeight.w400);
  static TextStyle get bodySmall =>
      _inter(12, FontWeight.w400, color: AppColors.textSecondary);

  // --- Labels --------------------------------------------------------------
  static TextStyle get labelLarge =>
      _inter(14, FontWeight.w600, letterSpacing: 0.1);
  static TextStyle get labelMedium =>
      _inter(12, FontWeight.w500, letterSpacing: 0.2);
  static TextStyle get labelSmall => _inter(10, FontWeight.w500,
      color: AppColors.textMuted, letterSpacing: 0.4);

  // --- Brand accent --------------------------------------------------------
  // Inter 600 (no Orbitron) — for member IDs and small brand labels
  static TextStyle get brandLabel =>
      _inter(11, FontWeight.w700, letterSpacing: 0.6);
}
