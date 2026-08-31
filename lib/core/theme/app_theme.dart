import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_geometry.dart';
import 'app_text_styles.dart';
import 'nuvo_tokens.dart';

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
      extensions: const [NuvoSemanticColors.standard],
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
        color: NuvoColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          side: const BorderSide(color: NuvoColors.border, width: 1),
        ),
        shadowColor: Colors.transparent,
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
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: NuvoColors.textMuted,
        ),
        labelStyle: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger),
        helperStyle: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        border: _inputBorder(NuvoColors.border),
        enabledBorder: _inputBorder(NuvoColors.border),
        focusedBorder: _inputBorder(NuvoColors.blue, width: 2),
        errorBorder: _inputBorder(NuvoColors.danger),
        focusedErrorBorder: _inputBorder(NuvoColors.danger, width: 2),
        floatingLabelStyle: AppTextStyles.labelMedium.copyWith(
          color: NuvoColors.blue,
        ),
      ),
      // Stray Material buttons should still read as physical Nuvo controls —
      // a modest elevation + navy shadow — even before a screen is migrated to
      // the NuvoButton widgets. Prefer the NuvoButton widgets for new work.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NuvoColors.blue,
          foregroundColor: NuvoColors.white,
          disabledBackgroundColor: NuvoColors.disabledSurface,
          disabledForegroundColor: NuvoColors.disabledText,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 17),
          textStyle: AppTextStyles.buttonLabel,
          side: const BorderSide(color: NuvoColors.navy, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NuvoRadii.button),
          ),
          elevation: 3,
          shadowColor: NuvoColors.navy,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NuvoColors.navy,
          backgroundColor: NuvoColors.surface,
          side: const BorderSide(color: NuvoColors.navy, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 17),
          textStyle: AppTextStyles.buttonLabel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NuvoRadii.button),
          ),
          elevation: 2,
          shadowColor: NuvoColors.navy,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NuvoColors.blue,
          backgroundColor: NuvoTokens.gray100,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: AppTextStyles.buttonLabel,
          side: const BorderSide(color: NuvoTokens.gray300, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NuvoRadii.md),
          ),
          elevation: 1,
          shadowColor: NuvoColors.navy,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: NuvoColors.surface,
        selectedColor: NuvoColors.icyBlue,
        disabledColor: NuvoColors.panel,
        labelStyle: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        secondaryLabelStyle: AppTextStyles.labelMedium.copyWith(
          color: NuvoColors.blue,
        ),
        side: const BorderSide(color: NuvoColors.border, width: 1.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
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
          borderRadius: BorderRadius.circular(NuvoRadii.md),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: NuvoColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: NuvoColors.surface,
        showDragHandle: true,
        dragHandleColor: NuvoColors.borderStrong,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: NuvoColors.border),
        ),
        shadowColor: NuvoColors.navy.withValues(alpha: 0.10),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NuvoColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          side: const BorderSide(color: NuvoColors.border),
        ),
      ),
    );
  }

  static ThemeData dark() => light();

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        borderSide: BorderSide(color: color, width: width),
      );
}
