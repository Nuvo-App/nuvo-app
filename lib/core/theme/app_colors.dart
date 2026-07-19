import 'package:flutter/material.dart';

final class NuvoColors {
  NuvoColors._();

  // ── Brand core ────────────────────────────────────────────────────────────────
  /// Primary action color — CTA, progress, chips.
  static const Color blue = Color(0xFF0165FC);

  /// Alias of [blue] for explicit call sites.
  static const Color actionBlue = blue;

  /// Gradient partner / pressed state.
  static const Color blue2 = Color(0xFF0165FC);

  /// Pressed / deeper variant — ink state.
  static const Color blueInk = Color(0xFF07152C);

  /// Light blue tint.
  static const Color blueLight = Color(0x330165FC);

  /// Primary dark — headlines, nav active state.
  static const Color navy = Color(0xFF07152C);

  /// Quiet structural ink used by legacy offset surfaces.
  static const Color inkNavy = Color(0x4D07152C);

  /// Slightly deeper navy for layered surfaces (alias of ink).
  static const Color navy2 = Color(0xFF07152C);

  /// Platinum — legacy alias.
  static const Color platinum = Color(0x1F07152C);

  /// Disabled / locked state.
  static const Color paleSlate = Color(0x8007152C);

  // ── Accent palette ────────────────────────────────────────────────────────────
  static const Color aqua = Color(0xFF718B79);
  static const Color coral = Color(0xFFC97968);
  static const Color sunshine = Color(0xFFD5AA63);

  // ── Page & surfaces ───────────────────────────────────────────────────────────
  /// Main page background — clean soft white.
  static const Color page = Color(0xFFFDFEFF);

  /// Alias of [page].
  static const Color pageIce = page;

  static const Color pageWarm = Color(0xFFFDFEFF);
  static const Color surface = Color(0xFFFDFEFF);
  static const Color card = surface;

  /// Light tint background — active pills, "you" row highlight.
  static const Color panel = Color(0x1F0165FC);

  static const Color inkWash = Color(0x1007152C);

  // ── Lines and tracks ──────────────────────────────────────────────────────────
  static const Color trackBg = Color(0x330165FC);
  static const Color divider = Color(0x2407152C);
  static const Color border = Color(0x3307152C);
  static const Color borderStrong = paleSlate;

  /// Solid grey hard-offset plate for secondary cards (CTA construction,
  /// grey instead of ink navy). Must read clearly against white faces.
  static const Color offsetGrey = Color(0x4007152C);

  // ── Legacy aliases kept stable for existing screens ───────────────────────────
  static const Color icyBlue = Color(0x1F0165FC);
  static const Color softBlue = Color(0x330165FC);
  static const Color lavenderRow = Color(0x1A0165FC);
  static const Color sectionBlue = icyBlue;
  static const Color bluePale = softBlue;
  static const Color blueSoft = blue2;
  static const Color navySoft = navy2;

  // ── Text & semantic ───────────────────────────────────────────────────────────
  static const Color muted = Color(0xE007152C);
  static const Color textMuted = Color(0xC207152C);
  static const Color textDim = Color(0xA307152C);
  static const Color white = surface;
  static const Color success = Color(0xFF66816C);
  static const Color danger = Color(0xFFB8665E);
  static const Color warning = Color(0xFFB17A43);
  static const Color amber = Color(0xFFB17A43);
  static const Color amberTint = Color(0xFFF4E7D8);
  static const Color gold = Color(0xFFC49A52);
  static const Color silver = Color(0xFFA8A29A);
  static const Color bronze = Color(0xFFA97752);

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
