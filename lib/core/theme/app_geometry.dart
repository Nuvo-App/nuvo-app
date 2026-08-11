import 'package:flutter/material.dart';

import 'app_colors.dart';

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
