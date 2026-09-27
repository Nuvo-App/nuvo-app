import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_shadows.dart';

abstract final class NuvoRadii {
  static const double xs = 12;
  static const double sm = 12;
  static const double md = 18;
  static const double button = 24;
  static const double lg = 26;
  static const double hero = 32;
  static const double pill = 999;

  // ── Semantic aliases for race UI ──────────────────────────────────────────────
  /// Small icon/number badge containers.
  static const double badge = 10;

  /// List containers, summary rows, surfaces.
  static const double card = 16;
}

/// Centralized spacing scale. Use these instead of arbitrary literals so
/// density is consistent across screens.
abstract final class NuvoSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Standard horizontal page padding used by Compete and sibling screens.
  static const double pageHorizontal = 22;

  // ── Page rhythm contract ──────────────────────────────────────────────────
  // Shared vertical cadence for root screens: header → first content →
  // sections → dock clearance. Screens keep their own layouts; these constants
  // keep the rhythm consistent without forcing identical compositions.
  /// Gap below a page header / tab strip before the first content block.
  static const double headerToContent = 12;

  /// Gap between sibling sections inside a page body.
  static const double section = 24;

  // ── First-viewport contract ────────────────────────────────────────────
  // See docs/ui/MAIN_SCREEN_LAYOUT_CONTRACT.md.
  /// Intentional breathing zone between the last visible first-viewport
  /// component and the floating dock — on top of the dock's own clearance
  /// (NuvoBottomNav.bottomPadding). Small by design: content should end
  /// confidently, not float in a void.
  static const double dockBreathing = 14;
}

/// Shared surface hierarchy. Not every piece of content is a card — pick the
/// lightest level that carries the information:
///
///   level 0 — no surface at all (feed rows, metadata, lightweight lists)
///   level 1 — quiet boundary (secondary groups, utility surfaces)
///   level 2 — strong Nuvo surface (hero cards, primary race moments, CTAs)
///   level 3 — filled / high-energy (live state, major selected moments)
abstract final class NuvoSurfaces {
  /// Level 1 — thin navy boundary, white fill, no shadow.
  static BoxDecoration quiet({double radius = NuvoRadii.card, Color? fill}) =>
      BoxDecoration(
        color: fill ?? NuvoColors.white,
        borderRadius: BorderRadius.circular(radius),
        border: NuvoBorders.quiet,
      );

  /// Level 2 — navy outline + hard offset shadow. Reserved for surfaces that
  /// deserve weight; do not default every container to this.
  static BoxDecoration strong({double radius = NuvoRadii.card, Color? fill}) =>
      BoxDecoration(
        color: fill ?? NuvoColors.white,
        borderRadius: BorderRadius.circular(radius),
        border: NuvoBorders.hero,
        boxShadow: AppShadows.hardSmall,
      );

  /// Level 3 — filled navy surface for live/critical moments.
  static BoxDecoration live({double radius = NuvoRadii.card}) => BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(radius),
        border: NuvoBorders.hero,
        boxShadow: AppShadows.hardSmall,
      );

  /// Level 3 variant — filled action blue for major selected/active moments.
  static BoxDecoration active({double radius = NuvoRadii.card}) =>
      BoxDecoration(
        color: NuvoColors.actionBlue,
        borderRadius: BorderRadius.circular(radius),
        border: NuvoBorders.hero,
        boxShadow: AppShadows.hardSmall,
      );
}

abstract final class NuvoBorders {
  static Border quiet = Border.all(color: NuvoColors.border, width: 1.25);
  static Border selected = Border.all(color: NuvoColors.actionBlue, width: 2);
  static Border hero = Border.all(color: NuvoColors.navy, width: 2);
  static Border action = Border.all(color: NuvoColors.navy, width: 2);
  static Border chip = Border.all(
    color: NuvoColors.actionBlue.withValues(alpha: 0.45),
    width: 1.5,
  );
  static Border brand = Border.all(color: NuvoColors.navy, width: 2);
  static Border subtle = quiet;

  /// Thin divider stroke for list containers and grouped surfaces.
  static Border divider = Border.all(color: NuvoColors.divider, width: 1);
}
