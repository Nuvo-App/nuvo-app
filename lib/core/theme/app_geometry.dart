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
}
