import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography is Inter only.
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
    letterSpacing: letterSpacing,
  );

  static TextStyle get displayLarge =>
      _inter(42, FontWeight.w900, height: 1.04);
  static TextStyle get displayMedium =>
      _inter(30, FontWeight.w800, height: 1.08);

  static TextStyle get headlineLarge =>
      _inter(25, FontWeight.w800, height: 1.12);
  static TextStyle get headlineMedium =>
      _inter(20, FontWeight.w700, height: 1.18);
  static TextStyle get titleLarge => _inter(17, FontWeight.w700);
  static TextStyle get titleMedium => _inter(15, FontWeight.w700);

  static TextStyle get bodyLarge => _inter(16, FontWeight.w500);
  static TextStyle get bodyMedium => _inter(14, FontWeight.w500);
  static TextStyle get bodySmall =>
      _inter(12, FontWeight.w500, color: AppColors.textSecondary);

  static TextStyle get labelLarge => _inter(14, FontWeight.w800);
  static TextStyle get labelMedium => _inter(12, FontWeight.w700);
  static TextStyle get labelSmall =>
      _inter(10, FontWeight.w500, color: AppColors.textMuted);

  static TextStyle get brandLabel => _inter(11, FontWeight.w800);
}
