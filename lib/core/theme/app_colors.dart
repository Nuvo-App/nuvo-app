import 'package:flutter/material.dart';

/// Brand color palette — matches nuvothrive.netlify.app
/// White-first, navy text, royal-blue CTAs.
final class NuvoColors {
  NuvoColors._();

  static const Color white = Color(0xFFFFFFFF);
  static const Color page = Color(0xFFF6FAFF); // app canvas
  static const Color sectionBlue = Color(0xFFEAF3FF); // hero / alt sections
  static const Color card = Color(0xFFFFFFFF);
  static const Color navy = Color(0xFF07152B); // primary text
  static const Color navySoft = Color(0xFF10233F);
  static const Color text = Color(0xFF081225);
  static const Color muted = Color(0xFF5B6B84);
  static const Color border = Color(0xFFDDE8F5);
  static const Color blue = Color(0xFF2F73EA); // CTA / primary
  static const Color blueSoft = Color(0xFF4D8DFF);
  static const Color bluePale = Color(0xFFDDEBFF);
  static const Color mint = Color(0xFF16C784); // success / verified
}

/// AppColors — aliases into NuvoColors so all existing screens
/// automatically inherit the light theme without code changes.
abstract final class AppColors {
  // Backgrounds
  static const Color background = NuvoColors.page;
  static const Color backgroundSoft = NuvoColors.sectionBlue;
  static const Color surface = NuvoColors.card;
  static const Color surfaceElevated = Color(0xFFF0F5FF);

  // Borders
  static const Color border = NuvoColors.border;
  static const Color borderStrong = Color(0xFFBDD3EE);

  // Brand / primary
  static const Color primary = NuvoColors.blue;
  static const Color primarySoft = NuvoColors.blueSoft;
  static const Color primaryDeep = Color(0xFF1E5FD4);

  // Accent palette
  static const Color dreamPurple = Color(0xFF7C6FF7);
  static const Color dreamPink = Color(0xFFF0ABFC);
  static const Color mint = NuvoColors.mint;

  // Semantic
  static const Color success = NuvoColors.mint;
  static const Color warning = Color(0xFFFFB86B);
  static const Color danger = Color(0xFFE8304A);

  // Text
  static const Color textPrimary = NuvoColors.navy;
  static const Color textSecondary = NuvoColors.muted;
  static const Color textMuted = Color(0xFF8899B0);
  static const Color textInverse = NuvoColors.white;

  // Legacy glass compat (used by GlassContainer)
  static const Color glassTint = Color(0x08000000);
  static const Color glassBorder = NuvoColors.border;

  // Legacy name aliases
  static const Color electricBlue = NuvoColors.blue;
  static const Color deepBlue = Color(0xFF1E5FD4);
  static const Color neonMint = NuvoColors.mint;
  static const Color hotAmber = Color(0xFFFFB86B);
}
