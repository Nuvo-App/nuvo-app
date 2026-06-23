import 'package:flutter/material.dart';

final class NuvoColors {
  NuvoColors._();

  // ── Page & surfaces ──────────────────────────────────────────────────────────
  static const Color page    = Color(0xFFFFFFFF); // pure white — clean canvas
  static const Color surface = Color(0xFFFFFFFF);
  static const Color panel   = Color(0xFFF7F9FC); // subtle section panels

  // ── Race track ───────────────────────────────────────────────────────────────
  static const Color trackBg  = Color(0xFFEDF1F7); // lane background
  static const Color divider  = Color(0xFFEAEFF7); // thin dividers

  // ── Legacy aliases (kept for code that references them) ──────────────────────
  static const Color icyBlue     = Color(0xFFEEF5FF);
  static const Color softBlue    = Color(0xFFDDEBFF);
  static const Color lavenderRow = Color(0xFFE7EAFF);

  // ── Core palette ─────────────────────────────────────────────────────────────
  static const Color navy  = Color(0xFF07152B);
  static const Color navy2 = Color(0xFF0B1E3A);
  static const Color blue  = Color(0xFF075BFF);
  static const Color blue2 = Color(0xFF2F73EA);

  // ── Semantic ─────────────────────────────────────────────────────────────────
  static const Color muted   = Color(0xFF66728A);
  static const Color border  = Color(0xFFDCE5F2);
  static const Color success = Color(0xFF16C784);
  static const Color danger  = Color(0xFFE5484D);

  // ── Aliases ──────────────────────────────────────────────────────────────────
  static const Color white      = surface;
  static const Color card       = surface;
  static const Color sectionBlue = icyBlue;
  static const Color bluePale   = softBlue;
  static const Color blueSoft   = blue2;
  static const Color navySoft   = navy2;
  static const Color mint       = success;
}

abstract final class AppColors {
  static const Color background       = NuvoColors.page;
  static const Color backgroundSoft   = NuvoColors.panel;
  static const Color surface          = NuvoColors.surface;
  static const Color surfaceElevated  = NuvoColors.icyBlue;
  static const Color border           = NuvoColors.border;
  static const Color borderStrong     = Color(0xFFB7C9E2);
  static const Color primary          = NuvoColors.blue;
  static const Color primarySoft      = NuvoColors.softBlue;
  static const Color primaryDeep      = NuvoColors.navy2;
  static const Color dreamPurple      = NuvoColors.softBlue;
  static const Color dreamPink        = Color(0xFFE7EAFF);
  static const Color mint             = NuvoColors.success;
  static const Color success          = NuvoColors.success;
  static const Color warning          = Color(0xFFFFB86B);
  static const Color danger           = Color(0xFFE8304A);
  static const Color textPrimary      = NuvoColors.navy;
  static const Color textSecondary    = NuvoColors.muted;
  static const Color textMuted        = Color(0xFF8B96A8);
  static const Color textInverse      = NuvoColors.white;
  static const Color glassTint        = Color(0x08FFFFFF);
  static const Color glassBorder      = NuvoColors.border;
  static const Color electricBlue     = NuvoColors.blue;
  static const Color deepBlue         = NuvoColors.navy2;
  static const Color neonMint         = NuvoColors.success;
  static const Color hotAmber         = Color(0xFFFFB86B);
}
