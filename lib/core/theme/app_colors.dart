import 'package:flutter/material.dart';

final class NuvoColors {
  NuvoColors._();

  // ── Brand core ────────────────────────────────────────────────────────────────
  /// Primary dark — headlines, outlines, nav active state.
  static const Color navy = Color(0xFF152238);

  /// Primary action color — CTA, progress, chips.
  static const Color blue = Color(0xFF2F7CFF);

  /// Alias of [blue] for explicit call sites.
  static const Color actionBlue = blue;

  /// Legacy gradient partner / pressed state.
  static const Color blue2 = blue;

  /// Pressed / deeper variant — ink state.
  static const Color blueInk = navy;

  /// Light blue tint.
  static const Color blueLight = Color(0xFFE1ECFF);

  /// Quiet structural ink used by legacy offset surfaces.
  static const Color inkNavy = Color(0xFF152238);

  /// Slightly deeper navy for layered surfaces (alias of ink).
  static const Color navy2 = navy;

  /// TrackSide deep navy — the primary dark screen background used by Arena.
  static const Color trackNavy = Color(0xFF071B35);

  /// TrackSide navy for radial glow and layered dark surfaces.
  static const Color trackNavyDeep = Color(0xFF061A33);

  /// TrackSide electric blue — primary action/accent on dark backgrounds.
  static const Color trackBlue = Color(0xFF2F7CFF);

  /// Brighter blue interaction state used for hover/pressed highlights.
  static const Color trackBlueBright = Color(0xFF4A9BFF);

  /// TrackSide off-white surface and text on dark backgrounds.
  static const Color trackWhite = Color(0xFFF8FAFD);

  /// TrackSide warm off-white for the lower panel surface.
  static const Color trackOffWhite = Color(0xFFFAF9F6);

  /// TrackSide primary dark text on the off-white panel.
  static const Color trackDarkText = Color(0xFF152238);

  /// TrackSide muted text for captions and timestamps.
  static const Color trackMutedText = Color(0xFF7F8795);

  /// TrackSide separator and divider on the panel.
  static const Color trackSeparator = Color(0xFFDDE1E6);

  /// TrackSide progress track and secondary rails on the panel.
  static const Color trackDarkProgress = Color(0xFF414A59);

  /// TrackSide participant-rail and secondary marker gray.
  static const Color trackGray = Color(0xFF5D738A);

  /// Platinum — legacy alias.
  static const Color platinum = Color(0xFFEFF3FA);

  /// Disabled / locked state.
  static const Color paleSlate = Color(0xFF929CAD);
  static const Color disabledSurface = Color(0xFFE8ECF2);
  static const Color disabledText = paleSlate;

  // ── Accent palette ────────────────────────────────────────────────────────────
  static const Color aqua = Color(0xFF718B79);
  static const Color coral = Color(0xFFC97968);
  static const Color sunshine = Color(0xFFD5AA63);

  // ── Page & surfaces ───────────────────────────────────────────────────────────
  /// Main page background — warm off-white / very pale blue-gray.
  static const Color page = Color(0xFFF7F9FC);

  /// Alias of [page].
  static const Color pageIce = page;

  static const Color pageWarm = page;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color secondarySurface = Color(0xFFEEF4FF);
  static const Color card = surface;

  /// Light tint background — active pills, "you" row highlight.
  static const Color panel = Color(0xFFE1ECFF);
  static const Color panelLight = Color(0xFFF0F5FF);

  static const Color inkWash = Color(0xFFF0F5FF);

  // ── Lines and tracks ──────────────────────────────────────────────────────────
  static const Color trackBg = Color(0xFFE1ECFF);
  static const Color divider = Color(0xFFDCE3EE);
  static const Color border = Color(0xFFDDE4EE);
  static const Color borderStrong = paleSlate;

  /// Solid grey hard-offset plate for secondary cards (CTA construction,
  /// grey instead of ink navy). Must read clearly against white faces.
  static const Color offsetGrey = navy;

  // ── Legacy aliases kept stable for existing screens ───────────────────────────
  static const Color icyBlue = panelLight;
  static const Color softBlue = panel;
  static const Color lavenderRow = panelLight;
  static const Color sectionBlue = icyBlue;
  static const Color bluePale = softBlue;
  static const Color blueSoft = blue2;
  static const Color navySoft = navy2;

  // ── Text & semantic ───────────────────────────────────────────────────────────
  static const Color muted = Color(0xFF5E6C85);
  static const Color textMuted = Color(0xFF7F8795);
  static const Color textDim = Color(0xFF929CAD);
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
