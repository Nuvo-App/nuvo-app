import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class NuvoRadii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double hero = 26;
  static const double pill = 999;
}

abstract final class NuvoBorders {
  static Border quiet = Border.all(color: NuvoColors.border);
  static Border selected = Border.all(color: NuvoColors.actionBlue, width: 1.5);
  static Border hero = Border.all(color: NuvoColors.inkNavy, width: 2);
  static Border action = Border.all(color: NuvoColors.inkNavy, width: 2);
  static Border chip = Border.all(color: NuvoColors.actionBlue, width: 1.4);
}
