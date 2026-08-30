import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_geometry.dart';
import 'app_shadows.dart';

/// Nuvo Design System v1.0 — tokens only.
///
/// This file is the single source of truth for colors, spacing, radii,
/// shadows, typography, animation, and avatar sizing. It does not import
/// business logic and does not contain widgets. Existing screens continue
/// using NuvoColors/AppColors while new work and refactors pull from here.
final class NuvoTokens {
  NuvoTokens._();

  // ── Brand core ─────────────────────────────────────────────────────────────

  /// Navy — icons, type, dark surfaces, selected nav, overlays.
  static const Color navy = NuvoColors.navy;

  /// Quiet structural edge for legacy borders and surfaces.
  static const Color inkNavy = NuvoColors.inkNavy;

  /// Action blue — CTA, progress arcs, chips, interactive only.
  static const Color actionBlue = NuvoColors.actionBlue;

  /// Legacy name kept as alias of [actionBlue].
  static const Color royalBlue = actionBlue;

  /// Clean soft-white page background.
  static const Color pageIce = NuvoColors.page;

  /// Page background alias.
  static const Color background = pageIce;

  /// Card surface — only interactive surfaces.
  static const Color card = NuvoColors.surface;

  // ── Semantic colors ────────────────────────────────────────────────────────

  /// Gold — first place only.
  static const Color gold = Color(0xFFF6B73C);

  /// Silver — second place only.
  static const Color silver = Color(0xFFAEB7C7);

  /// Bronze — third place only.
  static const Color bronze = Color(0xFFB67A44);

  /// Green — finished, verified, completed. Now allowed on success buttons.
  static const Color green = NuvoColors.success;
  static const Color greenBright = NuvoColors.successBright;

  /// Red — failure, rejected, destructive.
  static const Color red = NuvoColors.danger;
  static const Color redBright = NuvoColors.dangerBright;

  /// Amber — needs attention / almost finished / in review.
  static const Color amber = NuvoColors.warning;
  static const Color orange = Color(0xFFFF8C3A);

  // ── Gray scale ─────────────────────────────────────────────────────────────

  static const Color gray900 = Color(0xFF1E1E22);
  static const Color gray800 = Color(0xFF34363C);
  static const Color gray700 = Color(0xFF545861);
  static const Color gray600 = Color(0xFF6E727B);
  static const Color gray500 = Color(0xFF8F949E);
  static const Color gray400 = Color(0xFFB8BDC7);
  static const Color gray300 = Color(0xFFD9DDE3);
  static const Color gray200 = Color(0xFFEBEEF2);
  static const Color gray100 = Color(0xFFF4F6F8);

  // ── Spacing ────────────────────────────────────────────────────────────────

  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;
  static const double space64 = 64;

  // ── Radii ──────────────────────────────────────────────────────────────────

  static const double radius12 = 12;
  static const double radius18 = NuvoRadii.md;
  static const double radius20 = 20;
  static const double radius24 = NuvoRadii.button;
  static const double radius26 = NuvoRadii.lg;
  static const double radius28 = 28;
  static const double radius32 = NuvoRadii.hero;
  static const double radiusPill = NuvoRadii.pill;

  // ── Shadows ────────────────────────────────────────────────────────────────

  /// Compact hard offset.
  static const List<BoxShadow> hardSmall = AppShadows.hardSmall;

  /// Standard hard offset.
  static const List<BoxShadow> hardMedium = AppShadows.hardMedium;

  /// Hero hard offset.
  static const List<BoxShadow> hardLarge = AppShadows.hardLarge;

  /// Compact soft lift.
  static const List<BoxShadow> hardShadow3 = AppShadows.hardShadow3;

  /// Standard soft lift.
  static const List<BoxShadow> hardShadow4 = AppShadows.hardShadow4;

  /// Hero soft lift.
  static const List<BoxShadow> hardShadow5 = AppShadows.hardShadow5;

  /// Default interactive elevation.
  static const List<BoxShadow> hardShadow = hardMedium;

  /// Shadow 1 — legacy soft cards (prefer hardShadow*).
  static List<BoxShadow> get shadow1 => hardShadow3;

  /// Shadow 2 — sheets (soft, intentional).
  static List<BoxShadow> get shadow2 => const [
    BoxShadow(
      color: Color.fromRGBO(7, 21, 44, 0.07),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// Shadow 3 — floating nav (soft, intentional).
  static List<BoxShadow> get shadow3 => const [
    BoxShadow(
      color: Color.fromRGBO(7, 21, 44, 0.08),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];

  // ── Border ─────────────────────────────────────────────────────────────────

  static const Color borderColor = NuvoColors.border;
  static const double borderWidth = 1.25;
  static const double borderInkWidth = 2;

  static Border get borderInk => NuvoBorders.brand;

  static Border get borderAction => NuvoBorders.action;

  // ── Typography scale (Manrope) ─────────────────────────────────────────────

  static const String fontFamily = 'Manrope';

  static const double type40 = 40;
  static const double type32 = 32;
  static const double type28 = 28;
  static const double type24 = 24;
  static const double type20 = 20;
  static const double type18 = 18;
  static const double type16 = 16;
  static const double type14 = 14;
  static const double type12 = 12;

  static const FontWeight weightBold = FontWeight.w700;
  static const FontWeight weightSemiBold = FontWeight.w600;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightRegular = FontWeight.w400;

  // ── Animation ──────────────────────────────────────────────────────────────

  static const Duration duration220 = Duration(milliseconds: 220);
  static const Duration duration320 = Duration(milliseconds: 320);

  static const Curve curveEase = Curves.easeOutCubic;
  static const Curve curveSpring = Curves.easeOutBack;

  // ── Avatar sizes ───────────────────────────────────────────────────────────

  static const double avatar64 = 64;
  static const double avatar48 = 48;
  static const double avatar40 = 40;
  static const double avatar32 = 32;
  static const double avatar24 = 24;

  static const double avatarRingThickness = 2;

  // ── Elevation layers ─────────────────────────────────────────────────────────

  static const Color layerBackground = background;
  static const Color layerSurface = card;
  static const Color layerFloating = card;

  // ── Layout grid ────────────────────────────────────────────────────────────

  static const double margin = 24;
  static const double cardGap = 16;
  static const double sectionGap = 32;
}
