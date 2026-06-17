import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

abstract final class AppTheme {
  // Light status bar icons for the light app theme
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: NuvoColors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  /// Light theme — matches the nuvothrive.netlify.app aesthetic.
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NuvoColors.blue,
      brightness: Brightness.light,
    ).copyWith(
      primary: NuvoColors.blue,
      onPrimary: NuvoColors.white,
      secondary: NuvoColors.navySoft,
      tertiary: NuvoColors.mint,
      error: AppColors.danger,
      surface: NuvoColors.card,
      onSurface: NuvoColors.navy,
      surfaceContainerHighest: NuvoColors.sectionBlue,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: NuvoColors.page,
      canvasColor: NuvoColors.page,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,

      // Typography
      textTheme: TextTheme(
        displayLarge: AppTextStyles.displayLarge,
        displayMedium: AppTextStyles.displayMedium,
        headlineLarge: AppTextStyles.headlineLarge,
        headlineMedium: AppTextStyles.headlineMedium,
        titleLarge: AppTextStyles.titleLarge,
        titleMedium: AppTextStyles.titleMedium,
        bodyLarge: AppTextStyles.bodyLarge,
        bodyMedium: AppTextStyles.bodyMedium,
        bodySmall: AppTextStyles.bodySmall,
        labelLarge: AppTextStyles.labelLarge,
        labelMedium: AppTextStyles.labelMedium,
        labelSmall: AppTextStyles.labelSmall,
      ),

      // Cards
      cardTheme: CardThemeData(
        color: NuvoColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: NuvoColors.border, width: 1),
        ),
        shadowColor: const Color(0x0A000000),
      ),

      // App bar
      appBarTheme: AppBarTheme(
        backgroundColor: NuvoColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: AppTextStyles.titleLarge
            .copyWith(color: NuvoColors.navy),
        iconTheme: const IconThemeData(color: NuvoColors.navy),
        surfaceTintColor: Colors.transparent,
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NuvoColors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle:
            AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
        labelStyle: AppTextStyles.labelLarge
            .copyWith(color: AppColors.textSecondary),
        border: _inputBorder(NuvoColors.border),
        enabledBorder: _inputBorder(NuvoColors.border),
        focusedBorder: _inputBorder(NuvoColors.blue, width: 1.5),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.5),
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NuvoColors.blue,
          foregroundColor: NuvoColors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: AppTextStyles.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NuvoColors.blue,
          side: const BorderSide(color: NuvoColors.blue, width: 1.5),
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: AppTextStyles.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NuvoColors.blue,
          textStyle: AppTextStyles.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NuvoColors.blue,
          foregroundColor: NuvoColors.white,
          elevation: 0,
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: AppTextStyles.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: NuvoColors.sectionBlue,
        selectedColor: NuvoColors.bluePale,
        disabledColor: const Color(0xFFF0F0F0),
        labelStyle:
            AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        secondaryLabelStyle:
            AppTextStyles.labelMedium.copyWith(color: NuvoColors.blue),
        side: const BorderSide(color: NuvoColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // Misc
      dividerTheme: const DividerThemeData(
        color: NuvoColors.border,
        thickness: 1,
        space: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: NuvoColors.blue,
        inactiveTrackColor: NuvoColors.sectionBlue,
        thumbColor: NuvoColors.blue,
        overlayColor: NuvoColors.blue.withValues(alpha: 0.1),
        valueIndicatorColor: NuvoColors.navySoft,
        valueIndicatorTextStyle:
            AppTextStyles.labelMedium.copyWith(color: NuvoColors.white),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: NuvoColors.blue,
        linearTrackColor: NuvoColors.sectionBlue,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NuvoColors.navySoft,
        contentTextStyle:
            AppTextStyles.bodyMedium.copyWith(color: NuvoColors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  /// Legacy alias — callers using `AppTheme.dark()` now get the light theme.
  static ThemeData dark() => light();

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
}
