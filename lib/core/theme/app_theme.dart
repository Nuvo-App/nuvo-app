import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

abstract final class AppTheme {
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: NuvoColors.page,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: NuvoColors.blue,
          brightness: Brightness.light,
        ).copyWith(
          primary: NuvoColors.blue,
          onPrimary: NuvoColors.white,
          secondary: NuvoColors.navy,
          onSecondary: NuvoColors.white,
          tertiary: NuvoColors.aqua,
          error: NuvoColors.danger,
          surface: NuvoColors.surface,
          onSurface: NuvoColors.navy,
          surfaceContainerHighest: NuvoColors.panel,
          outline: NuvoColors.border,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: NuvoColors.page,
      canvasColor: NuvoColors.page,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      textTheme: TextTheme(
        displayLarge: AppTextStyles.displayLarge,
        displayMedium: AppTextStyles.displayMedium,
        displaySmall: AppTextStyles.displaySmall,
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
      cardTheme: CardThemeData(
        color: NuvoColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: NuvoColors.border),
        ),
        shadowColor: NuvoColors.blue.withValues(alpha: 0.12),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: NuvoColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: AppTextStyles.titleLarge.copyWith(
          color: NuvoColors.navy,
        ),
        iconTheme: const IconThemeData(color: NuvoColors.navy),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NuvoColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: NuvoColors.textMuted,
        ),
        labelStyle: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger),
        helperStyle:
            AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        border: _inputBorder(NuvoColors.border),
        enabledBorder: _inputBorder(NuvoColors.border),
        focusedBorder: _inputBorder(NuvoColors.blue, width: 1.8),
        errorBorder: _inputBorder(NuvoColors.danger),
        focusedErrorBorder: _inputBorder(NuvoColors.danger, width: 1.8),
        floatingLabelStyle: AppTextStyles.labelMedium.copyWith(
          color: NuvoColors.blue,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NuvoColors.blue,
          foregroundColor: NuvoColors.white,
          disabledBackgroundColor:
              NuvoColors.paleSlate.withValues(alpha: 0.38),
          disabledForegroundColor: NuvoColors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          textStyle: AppTextStyles.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          shadowColor: NuvoColors.blue.withValues(alpha: 0.28),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NuvoColors.navy,
          backgroundColor: NuvoColors.white,
          side: const BorderSide(color: NuvoColors.border, width: 1.2),
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: NuvoColors.white,
        selectedColor: NuvoColors.icyBlue,
        disabledColor: NuvoColors.panel,
        labelStyle:
            AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        secondaryLabelStyle:
            AppTextStyles.labelMedium.copyWith(color: NuvoColors.blue),
        side: const BorderSide(color: NuvoColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      ),
      dividerTheme: const DividerThemeData(
        color: NuvoColors.divider,
        thickness: 1,
        space: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: NuvoColors.blue,
        inactiveTrackColor: NuvoColors.trackBg,
        thumbColor: NuvoColors.blue,
        overlayColor: NuvoColors.blue.withValues(alpha: 0.12),
        valueIndicatorColor: NuvoColors.navy,
        valueIndicatorTextStyle: AppTextStyles.labelMedium.copyWith(
          color: NuvoColors.white,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: NuvoColors.blue,
        linearTrackColor: NuvoColors.trackBg,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NuvoColors.navy,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: NuvoColors.white,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: NuvoColors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: NuvoColors.white,
      ),
    );
  }

  static ThemeData dark() => light();

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
}
