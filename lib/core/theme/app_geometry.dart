import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class NuvoRadii {
  static const double xs = 10;
  static const double sm = 14;
  static const double md = 18;
  static const double lg = 24;
  static const double hero = 30;
  static const double pill = 999;
}

abstract final class NuvoBorders {
  static Border quiet = Border.all(color: NuvoColors.border);
  static Border selected = Border.all(
    color: NuvoColors.actionBlue.withValues(alpha: 0.35),
  );
  static Border hero = Border.all(color: NuvoColors.border);
  static Border action = Border.all(color: NuvoColors.border);
  static Border chip = Border.all(
    color: NuvoColors.actionBlue.withValues(alpha: 0.28),
  );
}
