import 'package:flutter/material.dart';

final class NuvoColors {
  NuvoColors._();

  // ── Brand core (Phase 0 lock) ─────────────────────────────────────────────────
  /// Primary action color — CTA, progress, chips.
  static const Color blue = Color(0xFF075BFF);

  /// Alias of [blue] for explicit call sites.
  static const Color actionBlue = blue;

  /// Gradient partner / pressed state.
  static const Color blue2 = Color(0xFF0547C7);

  /// Pressed / deeper variant — ink state.
  static const Color blueInk = Color(0xFF0547C7);

  /// Light blue tint.
  static const Color blueLight = Color(0xFF8EC3FF);

  /// Primary dark — headlines, nav active state.
  static const Color navy = Color(0xFF0A1A33);

  /// Ink navy — hard borders, hard shadows, ring track.
  static const Color inkNavy = Color(0xFF07152B);

  /// Slightly deeper navy for layered surfaces (alias of ink).
  static const Color navy2 = inkNavy;

  /// Platinum — legacy alias.
  static const Color platinum = Color(0xFFEFEFEF);

  /// Disabled / locked state.
  static const Color paleSlate = Color(0xFFC4C7CC);

  // ── Accent palette ────────────────────────────────────────────────────────────
  static const Color aqua = Color(0xFF22C7B8);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color sunshine = Color(0xFFFFC857);

  // ── Page & surfaces ───────────────────────────────────────────────────────────
  /// Main page background — ice.
  static const Color page = Color(0xFFF8FBFF);

  /// Alias of [page].
  static const Color pageIce = page;

  static const Color pageWarm = Color(0xFFF5F2EE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = surface;

  /// Light tint background — active pills, "you" row highlight.
  static const Color panel = Color(0xFFEDF4FE);

  static const Color inkWash = Color(0xFFF8FBFF);

  // ── Lines and tracks ──────────────────────────────────────────────────────────
  static const Color trackBg = Color(0xFFEAE8E2);
  static const Color divider = Color(0xFFEAE8E2);
  static const Color border = Color(0xFFEAE8E2);
  static const Color borderStrong = paleSlate;

  /// Solid grey hard-offset plate for secondary cards (CTA construction,
  /// grey instead of ink navy). Must read clearly against white faces.
  static const Color offsetGrey = Color(0xFF6B7280);

  // ── Legacy aliases kept stable for existing screens ───────────────────────────
  static const Color icyBlue = Color(0xFFEDF4FE);
  static const Color softBlue = Color(0xFF8EC3FF);
  static const Color lavenderRow = Color(0xFFEDF4FE);
  static const Color sectionBlue = icyBlue;
  static const Color bluePale = softBlue;
  static const Color blueSoft = blue2;
  static const Color navySoft = navy2;

  // ── Text & semantic ───────────────────────────────────────────────────────────
  static const Color muted = Color(0xFF8B8A85);
  static const Color textMuted = Color(0xFF8B8A85);
  static const Color textDim = Color(0xFF8B8A85);
  static const Color white = surface;
  static const Color success = Color(0xFF3E9C63);
  static const Color danger = Color(0xFFC25A4E);
  static const Color warning = Color(0xFFC97A2E);
  static const Color amber = Color(0xFFC97A2E);
  static const Color amberTint = Color(0xFFFBEEE0);
  static const Color gold = Color(0xFFD4A24C);
  static const Color silver = Color(0xFFA9ADB4);
  static const Color bronze = Color(0xFFB98657);

  // ── Avatar colors — flat, muted, never gradients ─────────────────────────────
  static const Color avatarTerracotta = Color(0xFFBE7B54);
  static const Color avatarOchre = Color(0xFFC79A44);
  static const Color avatarDustyBlue = Color(0xFF5E82A8);
  static const Color avatarSage = Color(0xFF6E8F6C);
  static const List<Color> avatarPalette = [
    avatarTerracotta,
    avatarOchre,
    avatarDustyBlue,
    avatarSage,
  ];

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
  static const Color dreamPink = NuvoColors.coral;
  static const Color mint = NuvoColors.success;
  static const Color success = NuvoColors.success;
  static const Color warning = NuvoColors.warning;
  static const Color danger = NuvoColors.danger;
  static const Color textPrimary = NuvoColors.navy;
  static const Color textSecondary = NuvoColors.muted;
  static const Color textMuted = NuvoColors.textMuted;
  static const Color textInverse = NuvoColors.white;
  static const Color electricBlue = NuvoColors.blue;
  static const Color deepBlue = NuvoColors.navy;
  static const Color neonMint = NuvoColors.aqua;
  static const Color hotAmber = NuvoColors.sunshine;
}
