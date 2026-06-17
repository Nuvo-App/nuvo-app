import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppGradients {
  // Primary brand gradient — blue
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDeep],
  );

  // Dream / accent gradient
  static const LinearGradient dream = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.dreamPurple, AppColors.primary],
  );

  // Victory / mint
  static const LinearGradient victory = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.mint, AppColors.primary],
  );

  // Warm / urgent
  static const LinearGradient hot = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.warning, AppColors.danger],
  );

  // Ambient card tint
  static LinearGradient cardAmbient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.primary.withValues(alpha: 0.07),
      AppColors.dreamPurple.withValues(alpha: 0.03),
    ],
  );

  // Top scrim (page background → transparent)
  static const LinearGradient topScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.background, Colors.transparent],
  );
}
