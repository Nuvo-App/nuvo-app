import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/nuvo_preview_style.dart';
import 'app_colors.dart';
import 'app_geometry.dart';
import 'app_text_styles.dart';

abstract final class AppTheme {
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: NuvoColors.page,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData light({
    NuvoPreviewStyle style = NuvoPreviewStyle.startingLine,
  }) {
    final visual = NuvoVisualTheme.forStyle(style);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: visual.action,
          brightness: Brightness.light,
        ).copyWith(
          primary: visual.action,
          onPrimary: NuvoColors.white,
          secondary: visual.ink,
          onSecondary: NuvoColors.white,
          tertiary: visual.accent,
          error: NuvoColors.danger,
          surface: visual.surface,
          onSurface: visual.ink,
          surfaceContainerHighest: visual.surfaceMuted,
          outline: visual.border,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: visual.page,
      canvasColor: visual.page,
      colorScheme: colorScheme,
      extensions: [visual],
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkRipple.splashFactory,
      fontFamily: GoogleFonts.manrope().fontFamily,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
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
        color: visual.surface,
        elevation: 0.6,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          side: BorderSide(color: visual.border),
        ),
        shadowColor: visual.ink.withValues(alpha: 0.10),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: visual.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: AppTextStyles.titleLarge.copyWith(color: visual.ink),
        iconTheme: IconThemeData(color: visual.ink),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: visual.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: NuvoColors.textMuted,
        ),
        labelStyle: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger),
        helperStyle: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        border: _inputBorder(NuvoColors.border),
        enabledBorder: _inputBorder(visual.border),
        focusedBorder: _inputBorder(visual.action, width: 1.5),
        errorBorder: _inputBorder(NuvoColors.danger),
        focusedErrorBorder: _inputBorder(NuvoColors.danger, width: 1.5),
        floatingLabelStyle: AppTextStyles.labelMedium.copyWith(
          color: visual.action,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: visual.action,
          foregroundColor: NuvoColors.white,
          disabledBackgroundColor: NuvoColors.paleSlate.withValues(alpha: 0.38),
          disabledForegroundColor: NuvoColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: AppTextStyles.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NuvoRadii.md),
          ),
          elevation: 0.5,
          shadowColor: visual.ink.withValues(alpha: 0.10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: visual.ink,
          backgroundColor: visual.surfaceMuted,
          side: BorderSide(color: visual.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: AppTextStyles.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NuvoRadii.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: visual.action,
          textStyle: AppTextStyles.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NuvoRadii.sm),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: visual.surface,
        selectedColor: visual.surfaceMuted,
        disabledColor: visual.surfaceMuted,
        labelStyle: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        secondaryLabelStyle: AppTextStyles.labelMedium.copyWith(
          color: visual.action,
        ),
        side: BorderSide(color: visual.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      ),
      dividerTheme: DividerThemeData(
        color: visual.border,
        thickness: 1,
        space: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: visual.action,
        inactiveTrackColor: visual.surfaceMuted,
        thumbColor: visual.action,
        overlayColor: visual.action.withValues(alpha: 0.12),
        valueIndicatorColor: visual.ink,
        valueIndicatorTextStyle: AppTextStyles.labelMedium.copyWith(
          color: NuvoColors.white,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: visual.action,
        linearTrackColor: visual.surfaceMuted,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: visual.ink,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: NuvoColors.white,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.md),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: visual.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: visual.surface,
        showDragHandle: true,
        dragHandleColor: visual.border,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: NuvoColors.border),
        ),
        shadowColor: visual.ink.withValues(alpha: 0.10),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: visual.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: visual.ink.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          side: BorderSide(color: visual.border),
        ),
      ),
    );
  }

  static ThemeData dark() => light(style: NuvoPreviewStyle.trackside);

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        borderSide: BorderSide(color: color, width: width),
      );
}
