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

  // ── Race UI semantic helpers ──────────────────────────────────────────────────
  // Aliases/compositions that make race-screen call sites readable.

  /// Section kicker / eyebrow. Alias of [eyebrow].
  static TextStyle get sectionKicker => eyebrow;

  /// Readable structural section title (14/w700/navy).
  /// Use for section headers like "Your races", "Up next", "Quick starts".
  /// Not uppercase — communicates structure without dashboard feel.
  static TextStyle get sectionTitle =>
      _manrope(14, FontWeight.w700, color: NuvoColors.navy, height: 1.2);

  /// Screen title (30/w800/navy, tight tracking).
  /// Use for the primary title on every tab screen: Compete, Verify, Crew, Profile.
  static TextStyle get screenTitle => _manrope(
    30,
    FontWeight.w800,
    color: NuvoColors.navy,
    height: 1.10,
    letterSpacing: -0.8,
  );

  /// Compact race row title (15/w700).
  static TextStyle get raceRowTitle =>
      _manrope(15, FontWeight.w700, height: 1.25);

  /// Compact race row meta line (12/w500, muted).
  static TextStyle get raceRowMeta =>
      _manrope(12, FontWeight.w500, color: AppColors.textMuted, height: 1.3);

  /// Featured race title on navy surface (20/w800, white).
  static TextStyle get featuredRaceTitle =>
      _manrope(20, FontWeight.w800, color: NuvoColors.white, height: 1.15);

  /// Stat number — large tabular figure for rank/score/placement.
  static TextStyle statLarge(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w800,
  }) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.textPrimary,
    height: 1.0,
    letterSpacing: -0.5,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Placement label — "1st", "2nd", "You're 3rd".
  static TextStyle placementLabel({
    Color? color,
    double size = 13,
    FontWeight weight = FontWeight.w800,
  }) => _manrope(
    size,
    weight,
    color: color ?? AppColors.textPrimary,
    height: 1.1,
  );
}
