import 'package:flutter/material.dart';

final class NuvoColors {
  NuvoColors._();

  // ── Brand core ────────────────────────────────────────────────────────────────
  /// Cornflower Blue — primary action color.
  static const Color blue = Color(0xFF5096F9);

  /// Lighter tint — hover / secondary accent.
  static const Color blue2 = Color(0xFF7AB3FA);

  /// Pressed / deeper variant — ink state.
  static const Color blueInk = Color(0xFF2B6FD4);

  /// Prussian Blue — primary text, headers.
  static const Color navy = Color(0xFF0A1A33);

  /// Slightly lighter navy for layered surfaces.
  static const Color navy2 = Color(0xFF13284A);

  /// Platinum — main background.
  static const Color platinum = Color(0xFFEFEFEF);

  /// Pale Slate — borders, secondary text, muted UI.
  static const Color paleSlate = Color(0xFFBBBEC4);

  // ── Accent palette ────────────────────────────────────────────────────────────
  static const Color aqua = Color(0xFF22C7B8);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color sunshine = Color(0xFFFFC857);
  static const Color violet = Color(0xFF7868FF);

  // ── Page & surfaces ───────────────────────────────────────────────────────────
  /// Main page background — brand Platinum.
  static const Color page = Color(0xFFEFEFEF);

  static const Color pageWarm = Color(0xFFF5F2EE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = surface;

  /// Very light blue tinted panel.
  static const Color panel = Color(0xFFF0F4FF);

  static const Color inkWash = Color(0xFFF8FAFF);
  static const Color glass = Color(0xF0FFFFFF);

  // ── Lines and tracks ──────────────────────────────────────────────────────────
  static const Color trackBg = Color(0xFFE4EAF5);
  static const Color divider = Color(0xFFDFE3EC);
  static const Color border = Color(0xFFE3E8F2);
  static const Color borderStrong = paleSlate;

  // ── Legacy aliases kept stable for existing screens ───────────────────────────
  static const Color icyBlue = Color(0xFFEBF2FF);
  static const Color softBlue = Color(0xFFD6E5FF);
  static const Color lavenderRow = Color(0xFFEDEBFF);
  static const Color sectionBlue = icyBlue;
  static const Color bluePale = softBlue;
  static const Color blueSoft = blue2;
  static const Color navySoft = navy2;

  // ── Text & semantic ───────────────────────────────────────────────────────────
  static const Color muted = Color(0xFF6B7591);
  static const Color textMuted = Color(0xFF9099B0);
  static const Color white = surface;
  static const Color success = Color(0xFF14A97B);
  static const Color danger = Color(0xFFE24D5C);
  static const Color warning = Color(0xFFF4A83D);
  static const Color gold = Color(0xFFD6A329);

  // ── Short aliases ─────────────────────────────────────────────────────────────
  static const Color mint = success;
  static const Color prize = gold;
}

abstract final class AppColors {
  static const Color background = NuvoColors.page;
  static const Color backgroundSoft = NuvoColors.panel;
  static const Color surface = NuvoColors.surface;
  static const Color surfaceElevated = NuvoColors.inkWash;
  static const Color border = NuvoColors.border;
  static const Color borderStrong = NuvoColors.borderStrong;
  static const Color primary = NuvoColors.blue;
  static const Color primarySoft = NuvoColors.softBlue;
  static const Color primaryDeep = NuvoColors.navy;
  static const Color dreamPurple = NuvoColors.violet;
  static const Color dreamPink = NuvoColors.coral;
  static const Color mint = NuvoColors.success;
  static const Color success = NuvoColors.success;
  static const Color warning = NuvoColors.warning;
  static const Color danger = NuvoColors.danger;
  static const Color textPrimary = NuvoColors.navy;
  static const Color textSecondary = NuvoColors.muted;
  static const Color textMuted = NuvoColors.textMuted;
  static const Color textInverse = NuvoColors.white;
  static const Color glassTint = Color(0xF0FFFFFF);
  static const Color glassBorder = Color(0x99FFFFFF);
  static const Color electricBlue = NuvoColors.blue;
  static const Color deepBlue = NuvoColors.navy;
  static const Color neonMint = NuvoColors.aqua;
  static const Color hotAmber = NuvoColors.sunshine;
}
